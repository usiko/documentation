## Accès protégé par credential

Le site est protégé par HTTP Basic Auth, sauf pour les requêtes provenant du
réseau local (`allow`/`deny` dans `nginx.conf.template`, combiné à
`satisfy any`) : ce sont deux façons alternatives d'être autorisé, pas deux
conditions cumulées.

La plage LAN et les identifiants viennent de variables d'environnement,
lues depuis un `.env` local au déploiement (jamais committé — voir
`.env.example` à la racine du dépôt) :

- `ALLOWED_CIDR` : injecté dans `nginx.conf.template` via `envsubst`, au
  démarrage du conteneur (mécanisme standard de l'image `nginx` officielle
  pour tout fichier `/etc/nginx/templates/*.template`).
- `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` : lus par
  `docker-entrypoint.d/05-generate-htpasswd.sh`, qui génère
  `/etc/nginx/.htpasswd` (hash APR1 via `openssl passwd -apr1`) à chaque
  démarrage du conteneur.

### Comportement par défaut (sans `.env`)

L'image définit `ALLOWED_CIDR=127.0.0.1/32` (ne correspond à aucun vrai
client) et génère un `.htpasswd` vide si `BASIC_AUTH_USER`/`PASSWORD` ne sont
pas fournis : tout accès est refusé (401) tant que rien n'est configuré.

### Déployer avec de vrais identifiants

Sur la machine de déploiement (NAS), à côté de `docker-compose.yml` :

```bash
cp .env.example .env
# éditer .env : ALLOWED_CIDR, BASIC_AUTH_USER, BASIC_AUTH_PASSWORD
```

`docker-compose.yml` charge ce fichier via `env_file` — `.env` ne doit
jamais être committé, sur le même principe que les `.env` des autres
services (cf. Retex Synology/GHCR).
