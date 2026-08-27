#projet #commonangular #angular #librairie

Workspace Angular CLI hébergeant une **librairie partagée** (`common`) de
composants/services réutilisables entre les projets front Angular d'usiko
(ex. [[TaskManager]], mongoManager, falidex-dashboard). Dépôt :
`usiko/common-angular` (public).

---

## But

Éviter de dupliquer du code (composants, services, utilitaires) entre les
projets Angular perso en le centralisant dans une librairie publiable, plutôt
que de copier-coller entre dépôts. Généré via `ng generate library`.

## État actuel

Le workspace racine (`common-angular`) ne contient qu'un seul projet Angular :
la librairie `common` (`projects/common`). Le composant placeholder généré
par le CLI (`lib-common`) a été retiré.

Quatre modules mergés dans `master` :

- **`auth/`** — authentification double-token (X-Token technique + JWT
  utilisateur), extraite de falidex-dashboard/TaskManager/mongoManager.
- **`charts/`** — 3 composants graphiques génériques (ApexCharts), extraits
  de TaskManager.
- **`config/`** — `ConfigService<T>` (voir §Services partagés).
- **`http/`** — `HttpService` (voir §Services partagés).

ESLint (`@angular-eslint`) et une CI GitHub Actions (lint + tests) sont en
place, ainsi qu'un pipeline de publication automatique vers une branche
`dist` (voir §Distribution).

## Services partagés

### `ConfigService<T>`

Charge un ou plusieurs fichiers de config JSON et les fusionne (les suivants
surchargent le premier, `Partial<T>`). Repris tel quel du service générique
déjà utilisé dans [[TaskManager]] (même fichier, même comportement) —
objectif : centraliser ce code dans `common-angular` plutôt que de le
dupliquer entre projets.

- Une sous-classe applicative peut fournir un `schema` (type `JSONSchemaType<T>`
  d'AJV) : la config fusionnée est alors validée avant d'être exposée, et
  `loadConfig` échoue avec une erreur explicite si elle ne le respecte pas.
  Sans schéma fourni, aucune validation (comportement historique inchangé).
- `getConfig()` renvoie la config chargée (`undefined` tant que
  `loadConfig(paths)` n'a pas émis).

### `HttpService`

Fine couche au-dessus de `HttpClient` avec les méthodes
`get`/`post`/`put`/`patch`/`delete`, sur le même principe de validation
optionnelle qu'`ConfigService` :

- Chaque méthode accepte un **schéma AJV optionnel** en paramètre (après
  l'URL, ou après le body pour `post`/`put`/`patch`). Fourni, la réponse est
  validée avant d'être émise par l'observable ; sinon comportement identique
  à `HttpClient` (pas de validation).
- Schéma non respecté → l'observable part en erreur (`Error` avec le détail
  AJV via `ajv.errorsText(...)`), pas d'émission de la valeur invalide.

```ts
interface IUser { id: number; name: string }

const userSchema: JSONSchemaType<IUser> = {
  type: 'object',
  properties: { id: { type: 'number' }, name: { type: 'string' } },
  required: ['id', 'name'],
  additionalProperties: false,
};

httpService.get<IUser>('/api/users/1', userSchema).subscribe(/* IUser garanti valide, ou erreur */);
httpService.get<IUser>('/api/users/1'); // sans schéma : comportement HttpClient classique
```

### Dépendance AJV et build ng-packagr

`ajv` est une dépendance runtime réelle des deux services (pas une
dépendance de dev). ng-packagr refuse par défaut qu'une librairie distribue
une dépendance `"dependencies"` qui n'est pas aussi une `peerDependency` (pour
éviter qu'un consommateur se retrouve avec une version d'AJV différente de la
sienne sans le savoir) :

> `Dependency ajv must be explicitly allowed using the "allowedNonPeerDependencies" option.`

Résolu en ajoutant `ajv` à `allowedNonPeerDependencies` dans
`projects/common/ng-package.json`, plutôt qu'en la mettant en
`peerDependencies` (elle n'a pas vocation à être fournie par l'appli
consommatrice).

## Module `auth/` — authentification double-token

Extraction de la logique d'authentification double-token (X-Token technique
+ JWT utilisateur) commune à falidex-dashboard, TaskManager et mongoManager.

- **`AuthTokenService`** — X-Token technique : hash SHA256 + dérivation,
  obtention avec retry, stockage avec expiration.
- **`JwtSessionService`** — persistance du JWT (+ payload applicatif
  optionnel), `isAuthenticated()`.
- **`xTokenInterceptor`** / **`jwtAuthInterceptor`** — deux
  `HttpInterceptorFn` indépendants (chacun n'injecte que son propre
  service), plutôt qu'un seul interceptor mêlant les deux préoccupations.
  `AUTH_INTERCEPTORS` fige l'ordre recommandé (X-Token puis JWT) pour
  `provideHttpClient(withInterceptors(AUTH_INTERCEPTORS))` — un retry
  X-Token retraverse ainsi le second interceptor et se voit réattacher le
  JWT.
- **`createAuthGuard(redirectTo)`** — factory de garde de route
  (`CanActivateFn`) basée sur `JwtSessionService`.
- **`AUTH_CONFIG`** (`InjectionToken<IAuthConfig>`) — pilote l'ensemble :
  URLs/clés/rôle exposés en fonctions (compatible `environment` statique ou
  config chargée à l'exécution), avec des hooks (`onSessionExpired`,
  `onUnauthorized`, `onXTokenExchangeFailed`) pour les effets de bord
  propres à chaque app (snackbar, navigation...).

`login`/`register`/`logout` réseau et l'intégration à un store applicatif
(NgRx Signals ou autre) restent volontairement du ressort de chaque app —
formes de réponse et intégrations trop différentes d'une app à l'autre.

## Module `charts/` — composants graphiques génériques (ApexCharts)

Extraction de 3 composants dumb de TaskManager, généralisés pour être
réutilisables par n'importe quelle app :

- **`LineChartComponent`** (`lib-line-chart`) — courbe multi-séries, avec
  palette de couleurs stable par `colorIndex` (indépendant de la position
  dans le tableau) et sélecteur de segment optionnel générique.
- **`DonutChartComponent`** (`lib-donut-chart`) — donut avec 3 modes de
  légende (`bottom` / `arrow` / `none`).
- **`HeatmapComponent`** (`lib-heatmap`) — grille de régularité façon graphe
  de contributions GitHub, paliers colorés par quantiles.

Aucune dépendance à une librairie d'icônes (icônes SVG inline) ; couleurs/
thème pilotables par tokens CSS `--common-chart-*` avec un fallback visuel
par défaut. `apexcharts`/`ng-apexcharts` sont en `peerDependencies` de la
lib — à installer côté app consommatrice, pas fournis par `common`.

Restent applicatifs (pas dans la lib) : navigation par période/carrousel de
swipe autour du donut, parsing des buckets backend, formatage de durée.

## Distribution — installation depuis un autre projet

La lib n'est pas publiée sur le registre npm public (pas de compte npm
dédié). Elle est distribuée **via git**, avec deux workflows GitHub Actions
dans `.github/workflows/` :

- **`ci.yml`** — sur chaque push `master` et chaque pull request :
  `npm ci` → `npm run lint` (ESLint) → `npm test` (Vitest).
- **`publish-dist.yml`** — sur chaque push `master` (ou déclenchement
  manuel) :
  1. build `projects/common` (`ng build common`, ng-packagr → Angular
     Package Format dans `dist/common`, avec son propre `package.json`) ;
  2. pousse ce résultat **en force** vers une branche dédiée `dist` (donc
     mouvante — écrasée à chaque run) ;
  3. crée un **tag git `vX.Y.Z`**, dérivé du champ `"version"` de
     `projects/common/package.json`, s'il n'existe pas déjà sur le dépôt.

Ce dernier workflow pousse avec le `GITHUB_TOKEN` par défaut fourni par
GitHub Actions à `usiko/common-angular` lui-même (pas un secret à créer) :
il faut juste que **Settings → Actions → General → Workflow permissions**
soit sur *"Read and write permissions"* sur ce repo, sinon le push vers
`dist`/le tag échoue en 403.

### Installer la lib

Dans le projet consommateur, en suivant la branche (toujours le dernier
build de `master`, non recommandé en prod) :

```bash
npm install github:usiko/common-angular#dist
```

Ou en épinglant une version précise (recommandé dès qu'une app est en
prod, cf. §Gestion des versions) :

```bash
npm install github:usiko/common-angular#v0.0.1
```

Le repo étant **public**, ces deux commandes fonctionnent telles quelles en
local comme en CI, sans token ni `.npmrc` — un `npm install`/`npm ci`
anonyme suffit.

### Gestion des versions

`dist` est une branche mouvante (écrasée à chaque run). Pour une référence
stable :

1. Le tag `vX.Y.Z` est dérivé du champ `"version"` de
   `projects/common/package.json`.
2. Si ce tag existe déjà sur le dépôt (version pas bumpée depuis la dernière
   publication), le job **ne le recrée pas**, mais publie quand même la
   branche `dist` — rien ne casse, mais aucune nouvelle version numérotée
   n'apparaît.
3. Pour publier une nouvelle version numérotée : incrémenter `"version"`
   dans `projects/common/package.json` (semver — patch/fix, minor/ajout non
   cassant, major/changement d'API cassant) **dans la même PR** que le
   changement de code, merger sur `master`. Le run suivant de
   `publish-dist.yml` publie `dist` **et** crée le tag correspondant.

Côté consommateur, épingler un tag (`#v0.0.1`) plutôt que suivre `#dist` dès
qu'une app est en production : `package.json` du consommateur reflète alors
explicitement la version utilisée, et un `npm install` ultérieur ne change
rien tant que la dépendance n'est pas mise à jour manuellement vers un
nouveau tag.

### Si le repo passe en privé — tokens CI

Si `usiko/common-angular` passe en **privé**, `npm install github:...`
échoue côté consommateur (accès HTTPS anonyme à GitHub impossible). Trois
options :

**1. En local, via SSH** (le plus simple si le repo reste visible par le
compte GitHub du développeur, clé SSH déjà configurée) :

```bash
npm install git+ssh://git@github.com/usiko/common-angular.git#v0.0.1
```

Aucun token à gérer, l'authentification passe par la clé SSH déjà en place
(`ssh -T git@github.com` doit répondre correctement).

**2. En CI, via un Personal Access Token (PAT) + réécriture d'URL git**
(recommandé pour un pipeline automatisé) — **ne jamais** mettre le token en
clair dans `package.json`/`package-lock.json` (il finirait commité) :

```bash
git config --global url."https://${COMMON_LIB_TOKEN}@github.com/".insteadOf "https://github.com/"
npm ci
```

- `COMMON_LIB_TOKEN` : un PAT GitHub *fine-grained*, scope lecture seule sur
  `usiko/common-angular` uniquement, stocké en secret CI **du projet
  consommateur** (`Settings → Secrets and variables → Actions`) — pas de
  `common-angular` lui-même.
- Étape GitHub Actions correspondante :

  ```yaml
  - name: Configure git auth for private common-angular
    run: git config --global url."https://${{ secrets.COMMON_LIB_TOKEN }}@github.com/".insteadOf "https://github.com/"
  - run: npm ci
  ```

**3. Deploy key en lecture seule** (le plus restreint, si un seul projet
consomme la lib) : générer une paire de clés SSH dédiée, ajouter la publique
en *deploy key* (lecture seule) sur `usiko/common-angular`
(`Settings → Deploy keys`), la privée en secret CI du consommateur, chargée
via une action type `webfactory/ssh-agent` avant `npm ci`. Plus de mise en
place que le PAT, mais le secret ne donne accès qu'à ce seul repo.

## Stack technique

- **Angular 21** (workspace CLI, `projectType: library`), builder
  `@angular/build:ng-packagr` pour la compilation de la librairie.
- **TypeScript strict** (`strict`, `noImplicitOverride`,
  `noPropertyAccessFromIndexSignature`, `noImplicitReturns`,
  `noFallthroughCasesInSwitch`, cible `ES2022`).
- **Vitest** comme test runner (`@angular/build:unit-test`), remplace Karma
  par défaut du CLI classique.
- **ESLint** (`@angular-eslint/schematics`, flat config `eslint.config.js`)
  + **Prettier** (`printWidth: 100`, guillemets simples, parser `angular`
  pour les templates HTML).
- **AJV** (`ajv`) pour la validation de schémas JSON, utilisée par
  `ConfigService`/`HttpService`.
- **ApexCharts** (`apexcharts`/`ng-apexcharts`, en `peerDependencies`) pour
  les composants de `charts/`.
- `ng-package.json` : point d'entrée `src/public-api.ts`, sortie compilée
  dans `dist/common` (à la racine du workspace, hors de `projects/`),
  `allowedNonPeerDependencies: ["ajv"]`.

## Structure

```
common-angular/
├── .github/workflows/
│   ├── ci.yml                # lint + tests, sur push master et PR
│   └── publish-dist.yml      # build + publie dist/common sur la branche `dist` + tag vX.Y.Z
├── angular.json               # config du workspace, un seul projet : "common"
├── eslint.config.js            # config ESLint racine (@angular-eslint)
├── tsconfig.json               # config TS racine, path mapping "common" -> ./dist/common
└── projects/
    └── common/
        ├── eslint.config.js   # config ESLint spécifique au projet "common"
        ├── ng-package.json    # config ng-packagr (entryFile, dest, allowedNonPeerDependencies)
        ├── package.json       # métadonnées npm de la librairie publiée (dont "version")
        ├── src/
        │   ├── public-api.ts  # surface publique exportée par la librairie
        │   ├── test-setup.ts  # polyfills tests (ex. ResizeObserver pour ApexCharts)
        │   └── lib/
        │       ├── auth/      # AuthTokenService, JwtSessionService, interceptors, guard, AUTH_CONFIG
        │       ├── charts/    # LineChart/DonutChart/HeatmapComponent
        │       ├── config/    # ConfigService<T>
        │       └── http/      # HttpService
        └── tsconfig.lib*.json / tsconfig.spec.json
```

Le `tsconfig.json` racine mappe l'import `"common"` vers `./dist/common` :
un projet consommateur peut donc importer la librairie compilée via
`import { ... } from 'common'` une fois le build effectué.

## Commandes utiles

```bash
npm ci                    # installe les dépendances
ng build common            # build de la librairie (production par défaut) -> dist/common
ng build common --configuration development --watch  # build en mode watch
ng test                    # tests unitaires (Vitest)
ng lint                    # ESLint (@angular-eslint)
npx prettier --check .      # formatage
ng generate component nom --project=common  # générer un composant/service dans la lib
```

## Points d'attention

- Pas de serveur de développement au sens applicatif (`ng serve`) : c'est
  une librairie, pas une application — le `README.md` racine, longtemps
  resté le boilerplate par défaut du CLI (mentionnant `ng serve`), a été
  réécrit pour documenter le projet réel (voir §Distribution ci-dessus,
  reprise de son contenu).
- Le workflow `publish-dist.yml` avait initialement un déclencheur
  `push: branches: [main]` alors que le repo utilise `master` comme branche
  par défaut — bug corrigé ([common-angular#6](https://github.com/usiko/common-angular/pull/6)),
  le workflow n'avait donc jamais tourné avant cette correction malgré un
  premier merge sur `master`.

## Liens
- [[TaskManager]] — origine du `ConfigService` et des composants `charts/`
  repris dans cette librairie
- mongoManager, falidex-dashboard — projets front consommateurs potentiels
