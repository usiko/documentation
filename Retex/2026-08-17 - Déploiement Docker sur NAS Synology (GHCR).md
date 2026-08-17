#retex #docker #synology #ghcr #mongomanager #devops

Retex sur la mise en place du déploiement de [[mongoManager]] (front Angular) et [[MongoManagerBackend]] (backend Rust) via images Docker publiées sur GitHub Container Registry (GHCR), déployées sur un NAS Synology (DS avec Container Manager) via Docker Compose.

But du document : garder une trace du cheminement (y compris les impasses) pour ne pas re-découvrir les mêmes pièges la prochaine fois qu'un déploiement Docker/Synology doit être mis en place.

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

> [!note] Variante avec MongoDB auto-hébergé
> Une version alternative du compose existe (Mongo local dans un conteneur `mongo:4.4` plutôt qu'Atlas) — utile si on ne veut pas dépendre d'Atlas. Le backend détecte tout seul `mongodb://` vs `mongodb+srv://` selon que `MONGO_HOST` contient un port (`mongo:27017` → `mongodb://`).

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

## 5. Leçons à retenir pour la prochaine fois

1. **Ne jamais coller de token/secret dans un chat** (même "éphémère", même "juste pour tester") — une fois dans l'historique, il est exposé, point final. Toujours passer par un champ dédié côté outil final (Container Manager, script SSH local, etc.), jamais transiter par la conversation.
2. **GHCR + Container Manager = piège connu.** Ne pas perdre de temps sur les scopes de token si un test direct (hors NAS, ex. `curl` avec le vrai flux bearer, ou même juste sur un autre PC) prouve déjà que le token/package fonctionnent. Le bug est dans l'UI Registre de Synology, pas dans les credentials.
3. **Sur Synology, aucun chemin Docker standard n'est fiable** — toujours partir de `/var/packages/ContainerManager/scripts/start-stop-status` (ou l'équivalent du paquet concerné) pour retrouver le vrai `ExecStart` et donc le vrai chemin de config, plutôt que de chercher `/etc/docker/*` à l'aveugle.
4. **Le Planificateur de tâches DSM n'a pas accès au socket Docker** même en tant que "root" configuré dans l'UI — mais il peut très bien écrire des fichiers et appeler `synosystemctl`. Utile de le savoir avant de perdre du temps à déboguer des permissions.
5. **`insecure-registries` fait sauter la vérification de certificat ET autorise le HTTP simple** — pas la peine de chercher un vrai certificat de confiance pour un registre strictement local/LAN, `insecure-registries` seul suffit.
6. **Toujours confirmer le dossier réellement utilisé par un Projet Container Manager** avant de déboguer un fichier de config qui "ne prend pas effet" — un des blocages de cette session venait d'un Projet pointant vers un autre chemin que celui édité en SSH (`docker inspect <container> --format '{{ range .Mounts }}{{ .Source }} -> {{ .Destination }}{{ println }}{{ end }}'` aurait dû être le premier réflexe, pas le dernier).
7. Le mécanisme hybride build-time/runtime pour `environment.prod.ts` (cf. §2) est un bon patron à reprendre pour d'autres projets Angular déployés en Docker : une seule image, configurable par déploiement sans rebuild, tout en gardant un `npm run build` local fonctionnel et pratique en dev.

## 6. Annexes — scripts utilisés

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
- [[mongoManager]]
- [[MongoManagerBackend]]
- [[Synology - notes générales]]
