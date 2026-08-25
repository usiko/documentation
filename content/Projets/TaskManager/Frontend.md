#taskmanager #angular #ngrx #ionic

Front du projet [[TaskManager]] (dépôt `TaskManager`). Ne contient **que**
le front — le backend est un dépôt séparé ([[Backend]]). Voir [[Routes]]
pour la table complète des routes Angular.

---

## Stack

- **Angular 20** standalone : `signal`/`computed`/`effect`,
  `input()`/`output()` partout — pas de `NgModule`, pas de décorateurs
  `@Input()`/`@Output()`.
- **NgRx Signals** (`@ngrx/signals`, `signalStore`, `withEntities`) pour
  l'état.
- **Ionic 8** (`@ionic/angular/standalone`) pour l'UI + **Capacitor 8** pour
  le natif.
- **TypeScript strict** (`strict`, `noImplicitOverride`,
  `noPropertyAccessFromIndexSignature`, `strictTemplates`).
- Icônes : `lucide-angular` + `ionicons` via un service `@services/icon`
  dédié.
- **Vitest** (builder `@angular/build:unit-test`, environnement `jsdom`) —
  pas de `karma.conf.js`, le `TestBed` (zone.js compris) est initialisé
  automatiquement par le builder.

## Architecture — découpage par feature

Chaque feature (`task`, `category`, `login`, `chrono`, `user`…) est une
route **lazy-loadée** (`<feature>/routes.ts`, déclarée dans
`app.routes.ts` — cf. [[Routes]]). Au sein d'une feature, le code est
découpé en **3 niveaux** :

### 1. `page` (`<feature>/<sub>/page/*.page.component.ts`)
Appelé par le router. Seul rôle : recevoir les params de route et les
propager aux composants `smart` via des **inputs**. Étend `PageBase`
(expose `pageEnter$`, un `ReplaySubject(1)` émis sur `ionViewWillEnter`).
Importe le `PageComponent` partagé (chrome : header, menu, FAB, progress
bar) et fournit une instance **locale** de `PageStore`/`PageFabStore`
(`providers: [...]`, pas de singleton).

### 2. `smart` (`<feature>/<sub>/smart/*.component.ts`)
Porte l'intelligence : `inject()` des stores NgRx et services, orchestration,
ouverture de modales, mutations. Reçoit `pageEnter$` et les params en
`input()` depuis la page. Compose des `dumb`, ne fait pas d'affichage
complexe lui-même.

### 3. `dumb` (`<feature>/.../dumb/*.component.ts` ou `shared/dumb/*`)
Affichage pur : uniquement `input()`/`output()`, **aucune** injection de
store/service métier. Réutilisable, testable, sans effet de bord.

## État — stores NgRx (`src/app/NGRX/`)

### Stores d'entités

Tout store gérant une collection passe par `createEntityMethods`
(`entities.store.ts`) :

```ts
@Injectable({ providedIn: 'root' })
export class TasksStore extends signalStore(
  withEntities<ITask>(),
  // Slices requis par createEntityMethods, sinon crash au runtime au
  // premier create/update/remove (pas d'erreur à la compilation).
  withState({ creationLoading: [] as string[], updateLoading: [] as string[], deleteLoading: [] as string[] }),
  withMethods((store) => createEntityMethods<ITask>()(store)),
) {}
```

`createEntityMethods` fournit : `add`/`create`/`update`/`remove`/`set`/
`clear`, leurs variantes `*_withoutStore`, `getById`/`getByIds`/`getFirst`/
`getLast`, `query(filters, sorts)`, `count`, `exists`, et
`loadByIds`/`addIdToLoad`.

### Flux de données (CQRS-léger via subjects)

Les mutations du store **émettent des subjects** d'événements CRUD
(`onCreate$`, `onAdd$`, `onUpdate$` avec `old`, `onRemove$`, `onSet$`,
`onClear$`, `onLoadIdsChange$`), exposés par `store.getEvents()` :

1. Un composant `smart` appelle `store.update(id, changes)` → l'état signal
   est patché **immédiatement** (UI optimiste) **et** un subject est émis.
2. Un **synchronizer** (`src/app/synchronizer/*.synchronizer.ts`,
   `@Injectable`) s'abonne à ces subjects et envoie les requêtes au backend
   via les services `data`. Il gère aussi la cohérence inter-entités.
3. Les composants ne font **jamais** d'appel HTTP direct : ils parlent aux
   stores, les synchronizers parlent au réseau.

> [!warning] Course sur les PUT successifs d'une même entité
> `TasksSynchronizer` répercutait `onUpdate$` vers le backend via un
> `mergeMap` global : plusieurs PUT sur la **même** tâche envoyés coup sur
> coup (ex. changer l'intervalle de récurrence plusieurs fois de suite avant
> que le premier ait répondu) partaient tous en parallèle, sans garantie
> d'ordre sur les réponses réseau — une réponse à une requête plus ancienne
> pouvait arriver après celle d'une requête plus récente et écraser
> (`setItem`) le store avec des champs obsolètes, jusqu'au prochain
> rechargement complet. Fix : `groupBy(id)` + `concatMap` (chaque PUT d'une
> même tâche attend la réponse du précédent avant de partir ; des tâches
> différentes restent traitées en parallèle entre elles). Voir
> [[Récurrence]]#Bugs corrigés.

### Chargement à la demande (par page)

**Aucun chargement de données au boot de l'app** : `AppComponent` ne fait
que brancher les handlers des synchronizers (`init()`). C'est **chaque
page** qui demande les stores dont elle a besoin, à son entrée :

- Le `smart` de la page appelle `store.load()` **uniquement** à chaque
  `pageEnter$` (données fraîches à chaque retour sur la page). `load()`
  émet `onLoadRequest$`, écouté par le synchronizer (`getAll` backend →
  `set`).
- Pas de `load()` en `ngOnInit` : `pageEnter$` étant un `ReplaySubject(1)`,
  l'entrée initiale est déjà couverte — un appel en plus enverrait la
  requête **en double**.
- Chargements ciblés (vue détail) : `addIdToLoad`/`removeIdToLoad`
  (`onLoadIdsChange$`).

### Stores de page

`PageStore`/`PageFabStore` (`NGRX/page/`) : état UI (titre, menu, FAB,
progress bar, action sheet). Fournis au niveau de **chaque page**
(`providers: [...]`), donc une instance par page — pas un singleton.

## Modèles

- Interfaces `I*` (ex. `ITask`), types/enums, valeurs par défaut exportées
  (`DEFAULT_TASK_RECURRENCE`). Pas de fonction dans les fichiers
  `*.model.ts` : toute logique dérivée d'une entité est une **méthode du
  store** correspondant (ex. `TasksStore.effectiveStatus()`), pas un helper
  exporté à côté du modèle.
- **Modèles backend (DTO)** : forme réseau typée dans `*-back.model.ts` à
  côté du data-service (`services/data/<feature>-data/`), interfaces
  préfixées `IBack*` — jamais confondues avec le modèle de store `I*`. La
  conversion DTO ↔ store est faite par l'adapter (`*-data.adapter.ts`).

Détail du modèle de récurrence : [[Modèle de données]] et [[Récurrence]].

## Conventions

- Nommage strict : `*.page.component.ts`, `*.component.ts` (smart/dumb),
  `*.store.ts`, `*.model.ts`, `*.service.ts`, `*.guard.ts`. Sélecteurs
  préfixés `app-`.
- Signals d'abord ; RxJS réservé aux flux (subjects d'événements,
  navigation, `takeUntil(destroy$)`).
- Pas de `flatMap`/`Array.prototype.flat` — boucle explicite ou `reduce`.
- Pas d'appel de méthode dans les templates pour l'affichage (signal/pipe
  pur uniquement) ; pas de `.emit()` inline (passe par une méthode
  `onXxx()`).
- Auth : `authGuard` (`services/auth`) protège `task`/`category`/`user`/
  `chrono` ; token géré via `http-interceptor`.

## Garde-fous review

- 🚫 Bloquant : `src/environments/environment.prod.ts` ne doit jamais
  contenir de valeurs vides (`''`) pour `tokenKey`/`derivationTokenKey`/
  `urls.dataServer` — résidu d'un `npm run build` local commité par erreur
  (déjà arrivé en prod, commit `648ed00`). `build-tools/prebuild.js`
  substitue les placeholders `{ENV:...}` au build ; en local sans les
  variables définies, il **vide** le fichier.
- Tout store d'entités déclare les 3 slices de loading
  (`creationLoading`/`updateLoading`/`deleteLoading`), sinon crash runtime
  au premier `create`/`update`/`remove`.
- Découpage page/smart/dumb respecté (un `dumb` n'injecte jamais de store).
- Aucune requête réseau hors synchronizer/service.
- Pas de chargement de données au boot ; `store.load()` sur `pageEnter$`
  uniquement, pour chaque store consommé (dumbs inclus).
- `PageStore`/`PageFabStore` fournis en `providers` de la page, pas en
  root.

## Liens
- [[TaskManager]]
- [[Backend]]
- [[Routes]]
- [[Modèle de données]]
- [[Récurrence]]
