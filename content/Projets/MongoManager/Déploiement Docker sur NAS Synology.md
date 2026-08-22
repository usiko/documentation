#docker #synology #ghcr #mongomanager #devops #déploiement

Documentation de référence sur le déploiement de [[mongoManager]] (front Angular) et [[MongoManagerBackend]] (backend Rust) via images Docker publiées sur GitHub Container Registry (GHCR), déployées sur un NAS Synology (DS avec Container Manager) via Docker Compose.

But du document : décrire l'architecture de déploiement actuelle, la configuration à jour, et documenter les problèmes déjà rencontrés (et leurs solutions) pour ne pas les re-découvrir la prochaine fois qu'il faut toucher au déploiement.

> [!info] Dernière mise à jour
> 2026-08-22 — ajout de `pull_policy: always`, section MongoDB auto-hébergé (auth SCRAM + volumes) et section `crypto.subtle`/contexte non sécurisé.

---

## 1. Contexte

Les deux repos (`mongoManager`, `MongoManagerBackend`) avaient déjà un `Dockerfile` chacun, mais seul le front avait un workflow GitHub Actions qui build + push l'image sur `ghcr.io` à chaque push sur `master`.

Objectif : pouvoir pull ces images depuis un NAS Synology et les faire tourner via `docker-compose`, en gardant tous les secrets (clés de chiffrement, mot de passe Mongo, etc.) uniquement dans un `.env` local au NAS — jamais sur GitHub.

## 2. Ce qui a été mis en place côté code

- **Backend** : `DockerFile` renommé en `Dockerfile` (convention standard), `EXPOSE` corrigé pour matcher le `PORT` par défaut (3000), ajout d'un `.dockerignore`, ajout du workflow `docker.yml` (miroir de celui du front) qui build + push `ghcr.io/usiko/mongomanagerbackend` sur push `master`.
- **Front** : le fichier `src/environments/environment.prod.ts` contient des placeholders `{ENV:TOKEN_HASH_KEY}` / `{ENV:DERIVATE_TOKEN_HASH_KEY}` / `{ENV:DATA_SERVER}`. Un mécanisme hybride a été mis en place :
  - `build-tools/prebuild.js` (hook npm `prebuild`) remplace ces placeholders par un `.env` local **si disponible** au moment du `npm run build` (utile en dev). S'il ne trouve pas la variable, il **laisse le placeholder intact** plutôt que de le vider.
  - `server/server.js` fait la substitution **au démarrage du conteneur**, à partir des variables d'environnement réellement passées par `docker-compose`. C'est ce mécanisme qui compte pour le déploiement Docker : l'image GHCR reste identique quel que soit le déploiement (NAS, prod, etc.), seule la conf au runtime change.
- `docker-compose.yml` (à la racine de `mongoManager`) + `.env.example` : lance `backend` + `frontend` à partir des images GHCR, avec les variables partagées (`TOKEN_HASH_KEY`, `DERIVATE_TOKEN_HASH_KEY`, `DATA_SERVER` doivent être identiques entre front et back, sinon `POST /token` échoue).

`docker-compose.yml` actuel (racine de `mongoManager`) :

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

> [!note] Variante avec MongoDB auto-hébergé
> Une version alternative du compose existe (Mongo local dans un conteneur plutôt qu'Atlas) — utile si on ne veut pas dépendre d'Atlas. Le backend détecte tout seul `mongodb://` vs `mongodb+srv://` selon que `MONGO_HOST` contient un port (`mongo:27017` → `mongodb://`). Cf. section 6 pour les pièges spécifiques à cette variante (auth SCRAM, volumes).

## 3. Le vrai sujet : pull d'une image **privée** GHCR depuis Container Manager

C'est ici que la majorité du temps est passée. Les packages GHCR publiés via `GITHUB_TOKEN` dans une Action sont **privés par défaut**, et les repos GitHub concernés sont privés aussi.

### 3.1 Piste évidente qui ne marchait pas : Registre Container Manager

Container Manager → Registre → ajout de `https://ghcr.io` avec un Personal Access Token (`read:packages`) → **`unauthorized`** au pull, quel que soit le scope du token (même testé avec un token full-access).

Diagnostic (sans toucher au NAS, juste via l'API GitHub) :
- Les workflows Docker des deux repos avaient bien tourné avec succès, images bien publiées (`ghcr.io/usiko/mongomanager:latest` confirmé dans les logs du job).
- Test direct depuis un terminal (Termux/a-Shell sur mobile, hors NAS) avec le vrai flux d'auth Docker Registry v2 (échange de bearer token en 2 étapes, **pas** un simple Basic Auth) → `200 OK`. Donc **le token et l'accès au package fonctionnent** — le problème est spécifique à Synology.

**Conclusion** : la fonctionnalité "Registre" de Container Manager est une réimplémentation maison de Synology, testée surtout contre Docker Hub — elle ne gère pas correctement le flux d'auth bearer en 2 étapes qu'utilise GHCR (et d'autres registres tiers conformes à l'OCI Distribution Spec). Ce n'est pas un souci de credentials.

> [!warning] Piège à connaître
> Un token GHCR avec toutes les permissions échoue exactement pareil qu'un token minimal si le vrai problème est ce bug d'implémentation côté Synology. Ne pas se focaliser sur les scopes du token si le test direct (hors NAS) fonctionne déjà.

### 3.2 Tentative : proxy pull-through local (`ghcr-proxy`)

Idée : déployer un `registry:2` (image officielle, publique, donc pull sans souci) configuré en **pull-through cache** vers `ghcr.io`, exposé en local sur le NAS (`192.168.1.19:9050`). Container Manager ne parle plus qu'à cette IP locale, jamais directement à GHCR — le vrai code Docker `distribution/distribution` gère l'auth bearer correctement, contrairement à l'UI Synology.

```yaml
# docker-compose.ghcr-proxy.yml
services:
  ghcr-proxy:
    image: registry:2
    container_name: ghcr-proxy
    restart: unless-stopped
    volumes:
      - ./registry-config.yml:/etc/docker/registry/config.yml:ro
      - ghcr-proxy-cache:/var/lib/registry
    ports:
      - '9050:5000'

volumes:
  ghcr-proxy-cache:
```

```yaml
# registry-config.yml
version: 0.1
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
proxy:
  remoteurl: https://ghcr.io
  username: usiko
  password: <TOKEN>
```

Puis dans le compose de mongoManager : `image: 192.168.1.19:9050/usiko/mongomanager:latest` (au lieu de `ghcr.io/usiko/...`).

**Nouveau blocage** : `Get "https://192.168.1.19:9050/v2/": http: server gave HTTP response to HTTPS client`. Docker part du principe qu'un registre est en HTTPS par défaut sauf indication contraire (`insecure-registries`).

### 3.3 Tentative : HTTPS avec certificat auto-signé

Pour éviter de toucher au démon Docker, essai de faire du proxy un vrai serveur HTTPS :
- DSM → Sécurité → Certificat ne propose (sur cette version) que "Let's Encrypt" (refuse une IP privée, besoin d'un vrai domaine public) ou "Importer" — pas d'option "certificat auto-signé" dans l'assistant.
- Génération manuelle en SSH :
```bash
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout privkey.pem -out cert.pem -days 3650 \
  -subj "/CN=192.168.1.19" \
  -addext "subjectAltName=IP:192.168.1.19"
```
- Ajout d'une section `tls:` dans `registry-config.yml`, montage des `.pem` dans le conteneur.
- Nouveau blocage : `x509: certificate signed by unknown authority` — le TLS fonctionne, mais le démon Docker ne fait pas confiance à un certificat auto-signé par défaut.
- La case "Faire confiance au certificat auto-signé SSL" dans l'UI Registre de Container Manager **ne suffit pas** — elle ne concerne que la fonctionnalité de navigation de Container Manager, pas le vrai démon qui fait le pull pour un déploiement de Projet/compose.

> [!tip] Ce n'est pas nécessaire au final
> `insecure-registries` (cf. section 4) fait sauter la vérification de certificat de toute façon (HTTPS non fiable **ou** HTTP simple, les deux passent) — donc pas besoin d'aller chercher un vrai certificat signé pour un usage strictement local/LAN. Le HTTPS auto-signé a été une fausse piste, mais les fichiers `cert.pem`/`privkey.pem` restent en place sans gêner (ils vivent dans un dossier partagé classique, pas dans les répertoires système gérés par le paquet Container Manager — donc pas de risque qu'ils soient écrasés à une mise à jour).

### 3.4 Piste abandonnée : reverse proxy DSM + domaine public

Idée un temps envisagée : utiliser le domaine déjà configuré (`syn.quentinondet.fr`) + le proxy inversé DSM + Let's Encrypt pour avoir un vrai certificat de confiance sur le proxy. **Rejetée volontairement** : ça exposerait le proxy (et indirectement le token GHCR) sur Internet, alors que le besoin est purement local (LAN). Toujours vérifier ce genre d'implication avant de router quoi que ce soit via un domaine public.

### 3.5 Solution finale : `insecure-registries` au niveau du vrai fichier de config du démon

Le vrai obstacle : Container Manager n'utilise **aucun** des chemins standards Linux/Docker.

- Pas de `/etc/docker/daemon.json`
- Pas de `/etc/docker/certs.d/`
- Pas de `/var/run/docker.sock` trouvable
- Aucun process `dockerd`/`containerd` visible via `ps aux | grep docker` dans certains contextes (le Planificateur de tâches DSM, notamment, n'a **pas** accès au socket Docker même configuré pour tourner en "root" — `permission denied`, probablement un contexte d'exécution différent d'une vraie session shell).

**Chemin réel trouvé** en lisant le script `/var/packages/ContainerManager/scripts/start-stop-status` (qui définit `ExecStart` du service systemd) :

```
/var/packages/ContainerManager/target/usr/bin/dockerd --config-file /var/packages/ContainerManager/etc/dockerd.json
```

Donc le vrai fichier de config est **`/var/packages/ContainerManager/etc/dockerd.json`**. `docker info` (en SSH, dans une vraie session — pas le Planificateur de tâches, qui bloque sur l'accès au socket) confirme au passage `Docker Root Dir: /volume3/@docker` et une entrée `Insecure Registries: 127.0.0.0/8` déjà présente par défaut (comportement Docker standard pour le loopback, rien à voir avec le fichier de config).

Solution :
```bash
# Sauvegarde de l'existant (renommé en .old, jamais écrasé silencieusement)
cp /var/packages/ContainerManager/etc/dockerd.json /var/packages/ContainerManager/etc/dockerd.json.old

# Fusion propre (garde toutes les clés existantes) via python3, ajout de insecure-registries
# cf. script setup-insecure-registry.sh dans le dossier ghcr-proxy du NAS

sudo synosystemctl restart pkg-ContainerManager-dockerd
```

Résultat : le pull passe enfin, aussi bien pour `ghcr-proxy` (192.168.1.19:9050) que pour les images mongoManager derrière.

> [!warning] Ce réglage ne survit peut-être pas à un redémarrage du NAS
> Le script `start-stop-status` de Container Manager appelle `$DockerUpdaterBin postinst updatedockerdconf` **à chaque démarrage du démon** (donc à chaque reboot du NAS, pas seulement aux mises à jour du paquet). Cet outil interne (binaire compilé, pas inspectable) pourrait régénérer `dockerd.json` et effacer l'ajout manuel. Pas testé avec certitude (aurait fallu rebooter le NAS pour vérifier).
>
> **Mitigation mise en place** : une tâche du Planificateur DSM déclenchée au **démarrage** (event "Boot-up", pas un horaire) rejoue le script de fusion + `synosystemctl restart` après chaque boot, en filet de sécurité. Comme cette tâche ne touche que l'écriture d'un fichier texte et un appel `synosystemctl` (pas le socket Docker directement), elle n'a pas le souci de permission rencontré plus tôt avec le Planificateur.

## 4. Fichiers de référence (chemins clés Synology, Container Manager)

| Chose | Chemin |
|---|---|
| Config du démon Docker | `/var/packages/ContainerManager/etc/dockerd.json` |
| Script de démarrage/arrêt du service | `/var/packages/ContainerManager/scripts/start-stop-status` |
| Unit systemd du démon | `/var/packages/ContainerManager/conf/systemd/pkg-ContainerManager-dockerd.service` |
| Data root Docker (images, conteneurs...) | `/volume3/@docker` (dépend du volume d'installation choisi) |
| Nom du service systemd | `pkg-ContainerManager-dockerd` |
| Commande de redémarrage du démon seul | `sudo synosystemctl restart pkg-ContainerManager-dockerd` |
| Binaire docker CLI | `/usr/local/bin/docker` (wrapper vers `/var/packages/ContainerManager/target/usr/bin/docker`) |

## 5. Mise à jour automatique des images (`pull_policy`)

Par défaut, `docker compose up -d` ne re-télécharge pas une image `:latest` déjà présente localement : sans action manuelle, le NAS reste bloqué sur l'image pullée lors du premier déploiement, même après un nouveau push sur `master` (qui republie pourtant `ghcr.io/usiko/mongomanager:latest` / `mongomanagerbackend:latest` à jour).

Solution retenue : `pull_policy: always` sur les deux services (cf. compose §2). Effet :
- Chaque `docker compose up -d` (relance manuelle, ou depuis l'UI Container Manager) re-télécharge d'abord l'image `:latest` avant de démarrer.
- Si l'image n'a pas changé depuis le dernier pull, Compose ne recrée **pas** les conteneurs déjà à jour — sans risque à relancer souvent.
- Nécessite Docker Compose v2 (`pull_policy` fait partie de la Compose Specification) ; c'est le cas de Container Manager sur DSM. Équivalent en CLI sans toucher au fichier : `docker compose up -d --pull always`.

> [!tip] Ça ne suffit pas seul pour un « vrai » auto-update
> `pull_policy: always` ne fait que garantir qu'**un `up` re-pull**. Pour que le NAS se mette à jour sans intervention manuelle, il faut aussi un déclencheur qui relance ce `up` périodiquement : une tâche **Planificateur de tâches DSM** (script `docker compose -f <chemin> up -d`) au démarrage du NAS et/ou à intervalle régulier (ex. quotidien). Alternative non retenue ici : Watchtower (polling continu dédié) — jugé superflu vu que `pull_policy: always` + une tâche planifiée suffisent au besoin.

## 6. MongoDB auto-hébergé : erreurs rencontrées

Concerne uniquement la variante « Mongo local » (cf. note §2) — pas le déploiement par défaut vers Atlas.

### 6.1 Échec d'authentification SCRAM (`Authentication failed`, code 18)

Symptôme : le backend refusait de démarrer / se connecter à Mongo avec une erreur SCRAM alors que `MONGO_USER`/`MONGO_PASSWORD` dans le `.env` semblaient corrects.

**Cause racine** : asymétrie entre deux mécanismes de substitution de Compose.
- La substitution `${VAR}` dans le YAML du compose (utilisée par le service `mongo` pour ses `MONGO_INITDB_ROOT_*`) **retire** les guillemets d'une valeur comme `MONGO_PASSWORD="motdepasse"`.
- Le mécanisme `env_file:` (utilisé pour passer les mêmes variables au conteneur `backend`) **ne retire pas** les guillemets — le conteneur reçoit littéralement `"motdepasse"` (avec les guillemets dans la valeur).

Résultat : le conteneur `mongo` s'initialise avec `motdepasse` (sans guillemets) mais le `backend` envoie `"motdepasse"` (avec) → échec SCRAM, alors que les deux `.env` semblent identiques à l'œil.

> [!warning] Piège à connaître
> Ne **jamais** mettre de guillemets dans les valeurs d'un `.env` consommé à la fois par `${VAR}` (YAML) et par `env_file:` — les deux mécanismes ne traitent pas les guillemets de la même façon. Retirer systématiquement les guillemets des valeurs de `.env` réglait le problème.

### 6.2 Le fix de `.env` seul ne suffisait pas : piège du volume nommé déjà initialisé

Même après avoir corrigé le `.env` (guillemets retirés), l'erreur SCRAM persistait. Cause : `MONGO_INITDB_ROOT_USER`/`MONGO_INITDB_ROOT_PASSWORD` ne sont appliqués par l'image Mongo **qu'à la toute première initialisation** d'un répertoire de données vide — le volume nommé existant (`mongo-manager_mongo-manager-data`) avait déjà été initialisé une première fois avec les (mauvais) identifiants comportant les guillemets, et les conservait malgré la correction du `.env`.

Fix : repartir d'un volume vierge.
```bash
docker rm mongo-manager-db          # nécessaire avant de pouvoir supprimer le volume ("volume is in use" sinon)
docker volume rm mongo-manager_mongo-manager-data
docker compose up -d                # ré-initialise le volume avec le .env corrigé
```

### 6.3 Tentative de bind-mount pour accéder aux fichiers de données (non aboutie)

Besoin : accéder directement aux fichiers de la base (`data/db`) depuis le NAS, plutôt que via un volume nommé opaque géré par Docker — remplacement tenté : `./data/db:/data/db` à la place du volume nommé.

Résultat : `IllegalOperation: Attempted to create a lock file on a read-only directory: /data/db`. Le conteneur Mongo tourne en uid `999` ; un `chown -R 999:999 data/db` côté NAS n'a **pas** résolu le problème, alors que le propriétaire Unix du dossier semblait pourtant correct côté NAS — probable interférence des ACL Synology (qui peuvent prévaloir sur les permissions POSIX classiques `chown`/`chmod`).

> [!warning] Non résolu / non confirmé
> Le dernier état de cette piste est une **recommandation non encore validée** : abandonner le bind-mount, revenir au volume nommé (`mongo-manager-data:/data/db`, cf. §6.2), et si le besoin est d'accéder aux données pour les sauvegarder, passer par des exports `mongodump` planifiés plutôt que par un accès direct aux fichiers bruts du volume. À confirmer/mettre à jour dans ce document une fois validé.

## 7. Bug `crypto.subtle` en contexte non sécurisé (HTTP)

Symptôme observé sur le NAS déployé en HTTP simple (pas de TLS/reverse-proxy) : le front chargeait normalement, mais **aucune requête réseau** n'était émise en cliquant sur "Se connecter" ou "S'inscrire" — pas d'onglet Network avec une requête en échec, littéralement zéro requête, et aucune erreur visible dans la console.

**Cause racine** : l'API Web Crypto (`crypto.subtle`) n'est disponible que dans un **contexte sécurisé** (HTTPS, ou `localhost`) — sur une origine HTTP simple (IP du NAS en `http://`), `crypto.subtle` vaut `undefined`. Le service d'auth du front (`AuthService`) utilisait `crypto.subtle.digest(...)` pour hasher le token technique (`X-Token`) **avant** l'appel HTTP — l'accès à une propriété `undefined` faisait échouer le hashing silencieusement en amont de toute requête réseau, d'où l'absence totale de trafic observé.

Fix : remplacement de `crypto.subtle` par [`@noble/hashes`](https://github.com/paulmillr/noble-hashes) (implémentation SHA-256 pure JS, auditée, sans dépendance), qui fonctionne indépendamment du contexte de sécurité de la page. Les méthodes de hashing sont passées de `Promise<string>` (async, `crypto.subtle.digest`) à `string` (synchrone, `@noble/hashes`).

> [!warning] Piège général à connaître
> Tout déploiement accessible uniquement en **HTTP simple sur un LAN** (typique d'un NAS sans reverse-proxy TLS devant) casse silencieusement `crypto.subtle` — et plus généralement toute API navigateur restreinte aux contextes sécurisés (ex. aussi : Clipboard API en écriture, certains Service Workers). À vérifier systématiquement si une app front utilise `crypto.subtle`, `navigator.clipboard`, etc. avant un déploiement HTTP-only.

En complément, pour rendre ce genre de panne silencieuse plus facile à diagnostiquer la prochaine fois :
- Ajout d'un log au démarrage de l'app listant les clés `{ENV:...}` non substituées (placeholder resté intact = variable d'env manquante côté conteneur).
- Différenciation claire des erreurs HTTP d'auth (`IAuthError`) : serveur injoignable (status `0`) vs réponse d'erreur du serveur (401/409/...) vs erreur générique, avec logs détaillés des appels `login`/`register`/`token`.

## 8. Leçons à retenir pour la prochaine fois

1. **Ne jamais coller de token/secret dans un chat** (même "éphémère", même "juste pour tester") — une fois dans l'historique, il est exposé, point final. Toujours passer par un champ dédié côté outil final (Container Manager, script SSH local, etc.), jamais transiter par la conversation.
2. **GHCR + Container Manager = piège connu.** Ne pas perdre de temps sur les scopes de token si un test direct (hors NAS, ex. `curl` avec le vrai flux bearer, ou même juste sur un autre PC) prouve déjà que le token/package fonctionnent. Le bug est dans l'UI Registre de Synology, pas dans les credentials.
3. **Sur Synology, aucun chemin Docker standard n'est fiable** — toujours partir de `/var/packages/ContainerManager/scripts/start-stop-status` (ou l'équivalent du paquet concerné) pour retrouver le vrai `ExecStart` et donc le vrai chemin de config, plutôt que de chercher `/etc/docker/*` à l'aveugle.
4. **Le Planificateur de tâches DSM n'a pas accès au socket Docker** même en tant que "root" configuré dans l'UI — mais il peut très bien écrire des fichiers et appeler `synosystemctl`. Utile de le savoir avant de perdre du temps à déboguer des permissions.
5. **`insecure-registries` fait sauter la vérification de certificat ET autorise le HTTP simple** — pas la peine de chercher un vrai certificat de confiance pour un registre strictement local/LAN, `insecure-registries` seul suffit.
6. **Toujours confirmer le dossier réellement utilisé par un Projet Container Manager** avant de déboguer un fichier de config qui "ne prend pas effet" — un des blocages de cette session venait d'un Projet pointant vers un autre chemin que celui édité en SSH (`docker inspect <container> --format '{{ range .Mounts }}{{ .Source }} -> {{ .Destination }}{{ println }}{{ end }}'` aurait dû être le premier réflexe, pas le dernier).
7. Le mécanisme hybride build-time/runtime pour `environment.prod.ts` (cf. §2) est un bon patron à reprendre pour d'autres projets Angular déployés en Docker : une seule image, configurable par déploiement sans rebuild, tout en gardant un `npm run build` local fonctionnel et pratique en dev.
8. **Jamais de guillemets dans un `.env` partagé entre `${VAR}` (YAML) et `env_file:`** — les deux mécanismes de substitution de Compose ne les traitent pas pareil, ce qui peut créer un mismatch de credentials silencieux (cf. §6.1).
9. **`MONGO_INITDB_ROOT_*` ne s'applique qu'à la toute première init d'un volume Mongo vide** — corriger le `.env` après coup ne suffit pas si le volume a déjà été initialisé avec de mauvaises valeurs ; il faut repartir d'un volume vierge (cf. §6.2).
10. **Les ACL Synology peuvent bloquer l'écriture d'un conteneur sur un bind-mount même après un `chown` Unix correct** — préférer un volume nommé Docker classique pour les données d'une base auto-hébergée sur Synology, et passer par des exports (`mongodump`) plutôt que par un accès direct aux fichiers si besoin des données brutes (cf. §6.3, non totalement confirmé).
11. **`crypto.subtle` est `undefined` hors contexte sécurisé (HTTPS/`localhost`)** — vérifier toute dépendance à des API Web restreintes aux contextes sécurisés avant un déploiement accessible uniquement en HTTP simple sur LAN (cf. §7).
12. **`pull_policy: always` ne suffit pas seul pour un auto-update** — il garantit qu'un `docker compose up` re-pull, encore faut-il un déclencheur (tâche planifiée DSM) qui relance ce `up` périodiquement (cf. §5).

## 9. Annexes — scripts utilisés

### `setup-cert.sh` (génération du certificat auto-signé, finalement pas indispensable mais gardé)
```bash
#!/bin/bash
set -e
IP="192.168.1.19"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout privkey.pem -out cert.pem -days 3650 \
  -subj "/CN=${IP}" \
  -addext "subjectAltName=IP:${IP}"
echo "Certificat genere dans $(pwd) :"
ls -la
```

### `setup-insecure-registry.sh` (la vraie solution)
```bash
#!/bin/bash
set -e

CONFIG_FILE="/var/packages/ContainerManager/etc/dockerd.json"
BACKUP_FILE="${CONFIG_FILE}.old"
ENV_FILE="/volume3/docker/mongoManager/.env"  # contient GHCR_PROXY=<ip>:<port>

GHCR_PROXY=$(grep -E '^GHCR_PROXY=' "$ENV_FILE" | cut -d '=' -f2- | tr -d '\r')

cp "$CONFIG_FILE" "$BACKUP_FILE"

python3 - "$BACKUP_FILE" "$CONFIG_FILE" "$GHCR_PROXY" << 'PYEOF'
import json, sys
backup_path, config_path, proxy = sys.argv[1], sys.argv[2], sys.argv[3]
with open(backup_path) as f:
    config = json.load(f)
registries = config.get("insecure-registries", [])
if proxy not in registries:
    registries.append(proxy)
config["insecure-registries"] = registries
with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
PYEOF

synosystemctl restart pkg-ContainerManager-dockerd
```

À rejouer via une tâche du Planificateur DSM déclenchée au **démarrage** (Boot-up), en filet de sécurité si `dockerd.json` est régénéré au reboot.

---

## Liens
- [[MongoManager]]
- [[mongoManager]]
- [[MongoManagerBackend]]
- [[Synology - notes générales]]
