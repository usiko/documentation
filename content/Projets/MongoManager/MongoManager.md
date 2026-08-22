#projet #mongomanager #angular #rust #mongodb

Dashboard de gestion de bases de données MongoDB, composé de deux dépôts :
[[mongoManager]] (front Angular) et [[MongoManagerBackend]] (backend Rust).
Voir aussi [[Déploiement Docker sur NAS Synology]] pour la mise en production
sur NAS.

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
  (cf. [[Déploiement Docker sur NAS Synology]] §7, cassait l'auth sur un NAS
  servi en HTTP simple).
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

## Liens
- [[mongoManager]]
- [[MongoManagerBackend]]
- [[Déploiement Docker sur NAS Synology]]
