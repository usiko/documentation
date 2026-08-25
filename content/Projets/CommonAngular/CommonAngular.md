#projet #commonangular #angular #librairie

Workspace Angular CLI destiné à héberger une **librairie partagée** (`common`)
de composants/services réutilisables entre les différents projets front
Angular d'usiko (ex. [[mongoManager]]). Dépôt : `usiko/common-angular`.

---

## But

Éviter de dupliquer du code (composants, services, utilitaires) entre les
projets Angular perso en le centralisant dans une librairie publiable, plutôt
que de copier-coller entre dépôts. Généré via `ng generate library`.

## État actuel

Le workspace racine (`common-angular`) ne contient qu'un seul projet
Angular : la librairie `common` (`projects/common`).

- La librairie expose toujours le composant placeholder généré par le CLI
  (`lib-common`, template `<p>common works!</p>`), pas encore retiré.
- Premiers services partagés ajoutés : `ConfigService` et `HttpService`
  (cf. §Services partagés) — *pas encore mergés dans `master`*, en cours de
  revue : [common-angular#3](https://github.com/usiko/common-angular/pull/3)
  (branche `feat/config-http-services`).

À mettre à jour au fur et à mesure que du contenu réel est ajouté à la
librairie.

## Services partagés

### `ConfigService<T>`

Charge un ou plusieurs fichiers de config JSON et les fusionne (les suivants
surchargent le premier, `Partial<T>`). Repris tel quel du service générique
déjà utilisé dans [[TaskManager]] (même fichier, même comportement) — objectif :
centraliser ce code dans `common-angular` plutôt que de le dupliquer entre
projets.

- Une sous-classe applicative peut fournir un `schema` (type `JSONSchemaType<T>`
  d'AJV) : la config fusionnée est alors validée avant d'être exposée, et
  `loadConfig` échoue avec une erreur explicite si elle ne le respecte pas.
  Sans schéma fourni, aucune validation (comportement historique inchangé).
- `getConfig()` renvoie la config chargée (`undefined` tant que
  `loadConfig(paths)` n'a pas émis).

### `HttpService`

Nouveau service (pas de préexistant ailleurs, contrairement à
`ConfigService`) : fine couche au-dessus de `HttpClient` avec les méthodes
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

## Stack technique

- **Angular 21** (workspace CLI, `projectType: library`), builder
  `@angular/build:ng-packagr` pour la compilation de la librairie.
- **TypeScript strict** (`strict`, `noImplicitOverride`,
  `noPropertyAccessFromIndexSignature`, `noImplicitReturns`,
  `noFallthroughCasesInSwitch`, cible `ES2022`).
- **Vitest** comme test runner (`@angular/build:unit-test`), remplace Karma
  par défaut du CLI classique — cf. `projects/common/README.md`, qui lui,
  généré automatiquement, mentionne encore Karma par erreur.
- **Prettier** (`printWidth: 100`, guillemets simples, parser `angular` pour
  les templates HTML).
- **AJV** (`ajv`) pour la validation de schémas JSON, utilisée par
  `ConfigService`/`HttpService` (cf. §Services partagés).
- `ng-package.json` : point d'entrée `src/public-api.ts`, sortie compilée
  dans `dist/common` (à la racine du workspace, hors de `projects/`),
  `allowedNonPeerDependencies: ["ajv"]`.

## Structure

```
common-angular/
├── angular.json              # config du workspace, un seul projet : "common"
├── tsconfig.json             # config TS racine, path mapping "common" -> ./dist/common
└── projects/
    └── common/
        ├── ng-package.json   # config ng-packagr (entryFile, dest)
        ├── package.json      # métadonnées npm de la librairie publiée
        ├── src/
        │   ├── public-api.ts # surface publique exportée par la librairie
        │   └── lib/
        │       ├── common.ts              # composant placeholder "lib-common"
        │       ├── common.spec.ts         # test associé
        │       ├── config/
        │       │   ├── config.service.ts       # ConfigService<T>
        │       │   └── config.service.spec.ts
        │       └── http/
        │           ├── http.service.ts         # HttpService
        │           └── http.service.spec.ts
        └── tsconfig.lib*.json / tsconfig.spec.json
```

Le `tsconfig.json` racine mappe l'import `"common"` vers `./dist/common` :
un projet consommateur peut donc importer la librairie compilée via
`import { ... } from 'common'` une fois le build effectué (ou via un lien
npm local le temps qu'elle ne soit pas publiée sur un registre).

## Commandes utiles

```bash
# Build de la librairie (production par défaut)
ng build common

# Build en mode watch (développement)
ng build common --configuration development --watch

# Tests unitaires (Vitest)
ng test

# Générer un nouveau composant/service dans la librairie
ng generate component nom --project=common
```

Le build compile `projects/common` et place le résultat publiable dans
`dist/common` (voir `ng-package.json`). Publication npm ensuite via
`cd dist/common && npm publish` (registre non défini pour l'instant — projet
pas encore publié).

## Points d'attention

- Pas de serveur de développement au sens applicatif (`ng serve`) : c'est une
  librairie, pas une application — le `README.md` racine généré par défaut
  par le CLI mentionne `ng serve`/`http://localhost:4200`, ce qui ne
  s'applique pas ici (pas d'application shell dans ce workspace pour l'instant).
- `.clinerules` présent à la racine configure un outil tiers (`rtk`, proxy
  CLI pour l'assistant Cline) — spécifique à cet outil, sans rapport avec le
  build/déploiement du projet.

## Liens
- [[mongoManager]] — projet front consommateur potentiel de cette librairie
- [[TaskManager]] — origine du `ConfigService` repris tel quel dans cette librairie
