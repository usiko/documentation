#projet #mongomanager #angular #rust #mongodb

Dashboard de gestion de bases de données MongoDB, composé de deux dépôts :
[[mongoManager]] (front Angular) et [[MongoManagerBackend]] (backend Rust).
Voir aussi [[Pull GHCR privé depuis Container Manager (Synology)]] pour les
détails du pull d'images privées sur le NAS (indépendant de ce projet).

---

## But

Centraliser la gestion de plusieurs bases MongoDB (connexions/clusters
personnels ou Atlas) dans une interface web unique, plutôt que de jongler
entre Compass, `mongosh` et les consoles cloud dispersées. Usage
perso/self-hosted, déployé sur un NAS Synology.

## Fonctionnalités

- **Authentification** : inscription/connexion (login + register), double
  token — JWT utilisateur + token technique `X-Token` (HMAC) pour les appels
  data. Changement de mot de passe (page dédiée).
- **Connexions Mongo cibles** : CRUD des connexions (host/utilisateur/mot de
  passe/couleur), test d'identifiants avant enregistrement et re-test d'une
  connexion déjà enregistrée, mot de passe chiffré en base (jamais en clair).
- **Bases de données** : liste des bases d'une connexion avec statistiques
  (nombre de collections/documents, taille sur disque), personnalisation
  (couleur, description), horodatage de dernière requête connue (si le
  profiling Mongo est activé côté cible). Duplication et export/import JSON
  d'une base.
- **Collections** : liste avec nombre de documents, export JSON, duplication
  au sein d'une même base, import (ajout ou remplacement complet du
  contenu).
- **Sauvegarde automatique** : planification par base (toutes les N heures,
  ou tous les N jours à une heure fixe — sélection via un `mat-timepicker`),
  rétention configurable (nombre de sauvegardes conservées), sauvegarde
  manuelle immédiate, restauration depuis une sauvegarde antérieure.
- **Confirmation par mot de passe** : les actions destructrices (suppression,
  restauration, remplacement de collection) redemandent le mot de passe
  courant avant exécution.

## Stack technique

### Front — [[mongoManager]]

- **Angular 21** standalone, signals partout (`signal`/`computed`/`effect`,
  `input()`/`output()`) — pas de `NgModule`.
- **NgRx Signals** (`signalStore`, `withEntities`) pour l'état, découpage
  page / smart / dumb par feature (pattern repris du repo voisin
  TaskManager).
- **Angular Material 21** (thème Material 3 via `mat.theme()`), incluant le
  `mat-timepicker` pour la sélection d'heure de backup.
- **TypeScript strict**.
- **`@noble/hashes`** (SHA-256 pur JS, audité) pour le hash du token
  technique — remplace `crypto.subtle`, indisponible hors contexte sécurisé
  (cf. §Bug `crypto.subtle` ci-dessous, cassait l'auth sur un NAS servi en
  HTTP simple).
- **Vitest** (runner de tests) + **ESLint**/`@angular-eslint`.
- Déploiement : petit serveur Node/Express (`server/server.js`) qui sert le
  build statique et substitue les variables d'environnement runtime, image
  publiée sur GHCR.

### Backend — [[MongoManagerBackend]]

- **Rust** + **Axum** (routing HTTP), driver **`mongodb`** officiel.
- Deux bases Mongo distinctes : une base **applicative** (utilisateurs,
  connexions cibles chiffrées, réglages de backup) configurée par variables
  d'environnement, et les bases **cibles** que l'utilisateur ajoute lui-même
  via `/connections`.
- Authentification en deux temps : token applicatif temporaire (`/token`,
  HMAC) puis JWT (`/auth`) pour les routes protégées.
- Connexions cibles chiffrées avec une clé dérivée de
  `SHA256(hash_mot_de_passe_utilisateur | pepper_serveur)` — un changement de
  mot de passe implique de ré-enregistrer les connexions existantes.
- **Scheduler** interne (poll périodique configurable) pour les sauvegardes
  automatiques.
- Déploiement : image Docker publiée sur GHCR.

---

## Routes front (Angular)

| Route | Garde | Description |
|---|---|---|
| `/login` | — | Connexion |
| `/register` | — | Inscription |
| `/server-error` | — | Page d'erreur (backend injoignable) |
| `/databases` | `authGuard` | Sélecteur "aucune base sélectionnée" |
| `/databases/:connectionId/:databaseName` | `authGuard` | Détail d'une base : collections, personnalisation, panneau de backup |
| `/connections` | `authGuard` | Liste et gestion des connexions Mongo cibles |
| `/user` | `authGuard` | Compte utilisateur (déconnexion, lien changement de mot de passe) |
| `/user/password` | `authGuard` | Changement de mot de passe |

`authGuard` redirige vers `/login` si `AuthService.isAuth()` (JWT valide) est
faux. `/databases` et `/connections` partagent une coquille commune
(`DatabaseShellPageComponent`, menu latéral persistant).

## Routes backend (Rust/Axum) et autorisations

Trois groupes de routes, empilés via des `Router` séparés dans `main.rs` :

| Groupe | Middleware(s) | Vérifie |
|---|---|---|
| **Libre** | aucun | — |
| **Token** | `verify_token_middleware` | Header `X-Token` (token applicatif HMAC, obtenu via `/token`) |
| **Protégé** | `verify_token_middleware` **+** `verify_jwt_middleware` | `X-Token` **et** `Authorization: Bearer <JWT>` |

### Libre (aucune authentification)

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/token` | Délivre le token applicatif (`X-Token`) — c'est justement ce qui permet ensuite d'appeler les routes "Token"/"Protégé" |

### Groupe « Token » (`X-Token` seul)

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/auth` | Connexion — renvoie un JWT |
| `POST` | `/register` | Inscription (username ≥ 3, mot de passe ≥ 8 caractères, `409` si nom déjà pris) — renvoie un JWT mais le front ne connecte pas l'utilisateur pour autant, il doit repasser par `/auth` |
| `GET` | `/register/available/{username}` | Disponibilité d'un nom d'utilisateur (validation en temps réel côté front) |
| `GET` | `/user/id/{user_id}` | Infos publiques d'un utilisateur par id |

### Groupe « Protégé » (`X-Token` + JWT)

| Méthode | Route | Description |
|---|---|---|
| `GET`/`POST` | `/persistence` | Persistance chiffrée générique par utilisateur |
| `GET` | `/user/` | Utilisateur courant (déduit du JWT) |
| `POST` | `/user/verify-password` | Re-vérifie le mot de passe courant (`401` sinon), sans émettre de nouveau JWT — utilisé avant une action destructrice |
| `PUT` | `/user/password` | Change le mot de passe (re-vérifie `current_password`, `401` sinon ; `400` si `new_password` < 8 caractères) *(pas encore mergé — [MongoManagerBackend#14](https://github.com/usiko/MongoManagerBackend/pull/14))* |
| `GET` | `/routes` | ⚠️ Nom trompeur : liste les **noms de collections de la base applicative** (`list_collection_names`), rien à voir avec les routes HTTP — probablement un endpoint de debug interne |
| `GET`/`POST` | `/connections` | Liste / création d'une connexion cible |
| `POST` | `/connections/test` | Teste des identifiants fournis sans les enregistrer |
| `PUT`/`DELETE` | `/connections/{id}` | Modification / suppression d'une connexion |
| `POST` | `/connections/{id}/test` | Re-teste une connexion déjà enregistrée |
| `GET` | `/connections/{id}/databases` | Bases d'une connexion (stats, personnalisation, dernière requête) |
| `PUT` | `/connections/{id}/databases/{name}/color` | Couleur de personnalisation (upsert) |
| `PUT` | `/connections/{id}/databases/{name}/description` | Description personnalisée (upsert) |
| `POST` | `/connections/{id}/databases/{source}/copy/{target}` | Duplique une base |
| `GET` | `/connections/{id}/databases/{name}/export` | Export JSON d'une base |
| `POST` | `/connections/{id}/databases/{target}/import` | Import JSON dans une base |
| `GET` | `/connections/{id}/databases/{name}/collections` | Collections d'une base (avec `estimated_document_count`) |
| `GET` | `/connections/{id}/databases/{name}/collections/{collection}/export` | Export JSON d'une collection |
| `POST` | `/connections/{id}/databases/{name}/collections/{source}/copy/{target}` | Duplique une collection dans la même base |
| `POST` | `/connections/{id}/databases/{name}/collections/{collection}/import` | Insère des documents sans toucher au contenu existant |
| `POST` | `/connections/{id}/databases/{name}/collections/{collection}/replace` | Vide puis réinsère (remplacement complet) |
| `GET`/`POST` | `/connections/{id}/databases/{name}/backup` | Statut de backup / déclenchement manuel |
| `POST` | `/connections/{id}/databases/{name}/backup/enable` | Active le backup automatique |
| `POST` | `/connections/{id}/databases/{name}/backup/disable` | Désactive le backup automatique |
| `PUT` | `/connections/{id}/databases/{name}/backup/settings` | Rétention et planification (`hourly`/`daily`, `time_of_day` en UTC) |
| `POST` | `/connections/{id}/databases/{name}/restore/{backup_id}` | Restaure une sauvegarde |

---

## Docker Compose

Chaque push sur `master` (des deux repos) construit et publie une image
Docker sur GHCR (`ghcr.io/usiko/mongomanager`, `ghcr.io/usiko/mongomanagerbackend`).
Sur le NAS, les deux services sont lancés via un unique `docker-compose.yml`
(à la racine de [[mongoManager]]) :

```yaml
services:
  backend:
    image: ghcr.io/usiko/mongomanagerbackend:latest
    pull_policy: always
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - '3000:3000'

  frontend:
    image: ghcr.io/usiko/mongomanager:latest
    pull_policy: always
    restart: unless-stopped
    depends_on:
      - backend
    environment:
      TOKEN_HASH_KEY: ${TOKEN_HASH_KEY}
      DERIVATE_TOKEN_HASH_KEY: ${DERIVATE_TOKEN_HASH_KEY}
      DATA_SERVER: ${DATA_SERVER}
    ports:
      - '8080:8080'
```

**Variables d'environnement partagées** : `frontend` reçoit
`TOKEN_HASH_KEY`/`DERIVATE_TOKEN_HASH_KEY`/`DATA_SERVER` en `environment:` ;
`backend` reçoit tous ses secrets via `env_file: .env`. Les deux doivent
partager les mêmes valeurs de `TOKEN_HASH_KEY`/`DERIVATE_TOKEN_HASH_KEY`,
sinon `POST /token` échoue.

**Substitution build-time/runtime (front)** : `src/environments/environment.prod.ts`
contient des placeholders `{ENV:TOKEN_HASH_KEY}` / `{ENV:DERIVATE_TOKEN_HASH_KEY}` /
`{ENV:DATA_SERVER}`. Mécanisme hybride :
- `build-tools/prebuild.js` (hook npm `prebuild`) les remplace par un `.env`
  local **si disponible** au moment du `npm run build` (utile en dev). S'il
  ne trouve pas la variable, il **laisse le placeholder intact** plutôt que
  de le vider.
- `server/server.js` fait la substitution **au démarrage du conteneur**, à
  partir des variables d'environnement réellement passées par
  `docker-compose`. C'est ce mécanisme qui compte pour le déploiement
  Docker : l'image GHCR reste identique quel que soit le déploiement (NAS,
  prod, ...), seule la conf au runtime change — une seule image sert donc
  n'importe quel déploiement sans rebuild.

**`pull_policy: always`** : chaque `docker compose up -d` re-télécharge
d'abord l'image `:latest` avant de (re)créer les conteneurs (si l'image n'a
pas changé, les conteneurs déjà à jour ne sont pas recréés). Combiné à une
tâche planifiée DSM (`docker compose -f <chemin> up -d`, au démarrage du NAS
et/ou à intervalle régulier), ça permet au NAS de rester à jour sans
intervention manuelle. `pull_policy` seul ne fait que garantir qu'un `up`
re-pull — encore faut-il le déclencheur périodique pour un vrai auto-update.

**Variante avec MongoDB auto-hébergé** : possible d'ajouter un service
`mongo` local plutôt que de dépendre d'Atlas — le backend détecte tout seul
`mongodb://` vs `mongodb+srv://` selon que `MONGO_HOST` contient un port
(`mongo:27017` → `mongodb://`). Cf. §MongoDB auto-hébergé ci-dessous pour les
pièges rencontrés avec cette variante.

**Pull des images privées GHCR sur le NAS** : voir
[[Pull GHCR privé depuis Container Manager (Synology)]] (indépendant de ce
projet — mêmes pièges pour n'importe quelle image privée déployée sur ce
NAS via Container Manager).

## MongoDB auto-hébergé : erreurs rencontrées

Concerne uniquement la variante « Mongo local » (cf. §Docker Compose) — pas
le déploiement par défaut vers Atlas.

### Échec d'authentification SCRAM (`Authentication failed`, code 18)

Symptôme : le backend refusait de démarrer / se connecter à Mongo avec une erreur SCRAM alors que `MONGO_USER`/`MONGO_PASSWORD` dans le `.env` semblaient corrects.

**Cause racine** : asymétrie entre deux mécanismes de substitution de Compose.
- La substitution `${VAR}` dans le YAML du compose (utilisée par le service `mongo` pour ses `MONGO_INITDB_ROOT_*`) **retire** les guillemets d'une valeur comme `MONGO_PASSWORD="motdepasse"`.
- Le mécanisme `env_file:` (utilisé pour passer les mêmes variables au conteneur `backend`) **ne retire pas** les guillemets — le conteneur reçoit littéralement `"motdepasse"` (avec les guillemets dans la valeur).

Résultat : le conteneur `mongo` s'initialise avec `motdepasse` (sans guillemets) mais le `backend` envoie `"motdepasse"` (avec) → échec SCRAM, alors que les deux `.env` semblent identiques à l'œil.

> [!warning] Piège à connaître
> Ne **jamais** mettre de guillemets dans les valeurs d'un `.env` consommé à la fois par `${VAR}` (YAML) et par `env_file:` — les deux mécanismes ne traitent pas les guillemets de la même façon. Retirer systématiquement les guillemets des valeurs de `.env` réglait le problème.

### Le fix de `.env` seul ne suffisait pas : piège du volume nommé déjà initialisé

Même après avoir corrigé le `.env` (guillemets retirés), l'erreur SCRAM persistait. Cause : `MONGO_INITDB_ROOT_USER`/`MONGO_INITDB_ROOT_PASSWORD` ne sont appliqués par l'image Mongo **qu'à la toute première initialisation** d'un répertoire de données vide — le volume nommé existant (`mongo-manager_mongo-manager-data`) avait déjà été initialisé une première fois avec les (mauvais) identifiants comportant les guillemets, et les conservait malgré la correction du `.env`.

Fix : repartir d'un volume vierge.
```bash
docker rm mongo-manager-db          # nécessaire avant de pouvoir supprimer le volume ("volume is in use" sinon)
docker volume rm mongo-manager_mongo-manager-data
docker compose up -d                # ré-initialise le volume avec le .env corrigé
```

### Tentative de bind-mount pour accéder aux fichiers de données (non aboutie)

Besoin : accéder directement aux fichiers de la base (`data/db`) depuis le NAS, plutôt que via un volume nommé opaque géré par Docker — remplacement tenté : `./data/db:/data/db` à la place du volume nommé.

Résultat : `IllegalOperation: Attempted to create a lock file on a read-only directory: /data/db`. Le conteneur Mongo tourne en uid `999` ; un `chown -R 999:999 data/db` côté NAS n'a **pas** résolu le problème, alors que le propriétaire Unix du dossier semblait pourtant correct côté NAS — probable interférence des ACL Synology (qui peuvent prévaloir sur les permissions POSIX classiques `chown`/`chmod`).

> [!warning] Non résolu / non confirmé
> Le dernier état de cette piste est une **recommandation non encore validée** : abandonner le bind-mount, revenir au volume nommé (`mongo-manager-data:/data/db`), et si le besoin est d'accéder aux données pour les sauvegarder, passer par des exports `mongodump` planifiés plutôt que par un accès direct aux fichiers bruts du volume. À confirmer/mettre à jour dans ce document une fois validé.

## Bug `crypto.subtle` en contexte non sécurisé (HTTP)

Symptôme observé sur le NAS déployé en HTTP simple (pas de TLS/reverse-proxy) : le front chargeait normalement, mais **aucune requête réseau** n'était émise en cliquant sur "Se connecter" ou "S'inscrire" — pas d'onglet Network avec une requête en échec, littéralement zéro requête, et aucune erreur visible dans la console.

**Cause racine** : l'API Web Crypto (`crypto.subtle`) n'est disponible que dans un **contexte sécurisé** (HTTPS, ou `localhost`) — sur une origine HTTP simple (IP du NAS en `http://`), `crypto.subtle` vaut `undefined`. Le service d'auth du front (`AuthService`) utilisait `crypto.subtle.digest(...)` pour hasher le token technique (`X-Token`) **avant** l'appel HTTP — l'accès à une propriété `undefined` faisait échouer le hashing silencieusement en amont de toute requête réseau, d'où l'absence totale de trafic observé.

Fix : remplacement de `crypto.subtle` par [`@noble/hashes`](https://github.com/paulmillr/noble-hashes) (implémentation SHA-256 pure JS, auditée, sans dépendance), qui fonctionne indépendamment du contexte de sécurité de la page. Les méthodes de hashing sont passées de `Promise<string>` (async, `crypto.subtle.digest`) à `string` (synchrone, `@noble/hashes`).

> [!warning] Piège général à connaître
> Tout déploiement accessible uniquement en **HTTP simple sur un LAN** (typique d'un NAS sans reverse-proxy TLS devant) casse silencieusement `crypto.subtle` — et plus généralement toute API navigateur restreinte aux contextes sécurisés (ex. aussi : Clipboard API en écriture, certains Service Workers). À vérifier systématiquement si une app front utilise `crypto.subtle`, `navigator.clipboard`, etc. avant un déploiement HTTP-only.

En complément, pour rendre ce genre de panne silencieuse plus facile à diagnostiquer la prochaine fois :
- Ajout d'un log au démarrage de l'app listant les clés `{ENV:...}` non substituées (placeholder resté intact = variable d'env manquante côté conteneur).
- Différenciation claire des erreurs HTTP d'auth (`IAuthError`) : serveur injoignable (status `0`) vs réponse d'erreur du serveur (401/409/...) vs erreur générique, avec logs détaillés des appels `login`/`register`/`token`.

## Liens
- [[mongoManager]]
- [[MongoManagerBackend]]
- [[Pull GHCR privé depuis Container Manager (Synology)]]
