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
- Premiers services/stores partagés ajoutés : `ConfigService`, `HttpService`
  et `createEntityMethods` (EntityStore) (cf. §Services et stores partagés) —
  *pas encore mergés dans `master`*, en cours de revue :
  [common-angular#3](https://github.com/usiko/common-angular/pull/3)
  (branche `feat/config-http-services`).

À mettre à jour au fur et à mesure que du contenu réel est ajouté à la
librairie.

## Services et stores partagés

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

### `createEntityMethods<T>()` (EntityStore)

Base commune **NgRx Signals** à tout store de collection, repris tel quel du
`entities.store.ts` de [[TaskManager]] (même pattern utilisé dans
[[chatVault]]). C'est le socle générique décrit dans
[[Architecture Store et Synchronizer]] — voir cette note pour la vue
d'ensemble (page/smart/dumb, synchronizer, chargement à la demande).

S'utilise avec `withEntities` d'`@ngrx/signals/entities` :

```ts
@Injectable({ providedIn: 'root' })
export class TasksStore extends signalStore(
  withEntities<ITask>(),
  // Slices REQUIS par createEntityMethods, cf. point d'attention ci-dessous.
  withState({ creationLoading: [] as string[], updateLoading: [] as string[], deleteLoading: [] as string[] }),
  withMethods((store) => createEntityMethods<ITask>()(store)),
) {}
```

Fournit :
- **CRUD** : `add`/`create`/`update`/`remove`/`set`/`clear`, variantes
  `*_withoutStore` (émettent l'événement sans toucher au store — utilisé
  côté "attendre la réponse backend avant d'afficher").
- **Lecture** : `getById`/`getByIds`/`getFirst`/`getLast`, `count`, `exists`.
- **`query(filters, sorts)`** : filtrage (`eq`/`ne`/`gt`/`lt`/`contains`) et
  tri multi-critères, en `Signal<T[]>`.
- **Chargement ciblé** : `loadByIds`/`addIdToLoad`/`removeIdToLoad`, et
  `load()` (demande de chargement complet, écoutée par le synchronizer).
- **Suivi de mutations en cours** (`isCreationLoading`/`isUpdateLoading`/
  `isDeleteLoading`, à binder sur un spinner) et **événements CRUD**
  (`getEvents()` : `onAdd$`/`onCreate$`/`onUpdate$` (avec `old`)/`onRemove$`/
  `onSet$`/`onClear$`/`onLoadIdsChange$`/`onLoadRequest$`), consommés par un
  synchronizer — jamais directement par un composant.

> [!warning] Point d'attention (déjà source de bugs dans TaskManager)
> Tout store qui utilise `createEntityMethods` **doit** déclarer
> `withState({ creationLoading: [], updateLoading: [], deleteLoading: [] })` :
> ces slices sont patchés par `create`/`update`/`remove` mais ne sont **pas**
> créés par `createEntityMethods` lui-même. Sans eux, ça compile et charge
> sans erreur, mais ça **crashe au runtime** au premier appel
> (`TypeError: store.updateLoading is not a function`).

### Dépendances non-peer et build ng-packagr

`ajv` et `uuid` sont des dépendances runtime réelles de la lib (pas de dev).
ng-packagr refuse par défaut qu'une librairie distribue une dépendance
`"dependencies"` qui n'est pas aussi une `peerDependency` (pour éviter qu'un
consommateur se retrouve avec une version différente de la sienne sans le
savoir) :

> `Dependency ajv must be explicitly allowed using the "allowedNonPeerDependencies" option.`

Résolu en ajoutant `ajv` et `uuid` à `allowedNonPeerDependencies` dans
`projects/common/ng-package.json`, plutôt qu'en les mettant en
`peerDependencies` (elles n'ont pas vocation à être fournies par l'appli
consommatrice — contrairement à `@ngrx/signals`, qui lui **est** en
`peerDependency` : la version doit rester alignée avec celle déjà utilisée
par l'appli consommatrice pour son propre state).

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
  `ConfigService`/`HttpService`.
- **NgRx Signals** (`@ngrx/signals`, `@ngrx/signals/entities`) pour
  `createEntityMethods` (EntityStore), en `peerDependency`.
- **`uuid`** (`v6`) pour la génération d'id côté `EntityStore.create()`.
- `ng-package.json` : point d'entrée `src/public-api.ts`, sortie compilée
  dans `dist/common` (à la racine du workspace, hors de `projects/`),
  `allowedNonPeerDependencies: ["ajv", "uuid"]`.

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
        │       ├── http/
        │       │   ├── http.service.ts         # HttpService
        │       │   └── http.service.spec.ts
        │       └── entity-store/
        │           ├── entity-store.ts         # createEntityMethods<T>()
        │           └── entity-store.spec.ts
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
- [[TaskManager]] — origine du `ConfigService` et de l'`EntityStore` repris tels quels dans cette librairie
- [[chatVault]] — autre projet utilisant le même pattern EntityStore/synchronizer
- [[Architecture Store et Synchronizer]] — vue d'ensemble de l'architecture (page/smart/dumb, stores, synchronizers) que ces stores partagés viennent outiller
