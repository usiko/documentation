## Accès protégé par credential

Le site est protégé par HTTP Basic Auth, sauf pour les requêtes provenant du
réseau local (`allow`/`deny` dans `nginx.conf`, combiné à `satisfy any`) : ce
sont deux façons alternatives d'être autorisé, pas deux conditions cumulées.

L'image Docker embarque un fichier `/etc/nginx/.htpasswd` vide (aucun
utilisateur valide) : tant qu'aucun vrai fichier n'est fourni, l'accès depuis
le LAN reste libre mais toute requête venant d'ailleurs reçoit un 401.

### Provisionner les vrais identifiants (hors dépôt Git)

Sur le NAS (ou toute machine avec `apache2-utils`/`httpd-tools` installé) :

```bash
htpasswd -B -c .htpasswd <utilisateur>
```

Puis monter ce fichier dans le conteneur, par exemple dans `docker-compose.yml` :

```yaml
services:
  documentation:
    volumes:
      - ./secrets/.htpasswd:/etc/nginx/.htpasswd:ro
```

Le fichier `.htpasswd` ne doit jamais être committé — il contient des hachages
de mots de passe. Garder ce fichier uniquement sur la machine de déploiement,
comme pour les `.env` des autres services (cf. Retex Synology/GHCR).
