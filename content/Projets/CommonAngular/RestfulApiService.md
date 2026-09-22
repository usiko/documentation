#commonangular #angular #rest #api

Service générique de la librairie `common` ([[CommonAngular]]) implémentant
le **CRUD RESTful** d'une ressource, paramétré par le modèle front
(`TFront`), le DTO backend (`TBack`) et le nom du champ identifiant
(`TIdKey`, `'id'` par défaut). Objectif : ne plus réécrire la
même couche HTTP CRUD dans chaque data-service de chaque projet — le
data-service applicatif ne fournit plus qu'une URL et des adapters de
conversion.

Fichiers : `projects/common/src/lib/restful-api/restful-api.service.ts` et
`restful-api.model.ts`.

---

## Principe

Un data-service classique (cf. `TaskDataService` dans [[Frontend]]) répète
toujours les quatre mêmes blocs : construire l'URL, appeler `HttpClient`,
convertir le DTO backend en modèle front, convertir le modèle front en
payload backend. `RestfulApiService` absorbe ces quatre blocs :

- l'**URL** est configurée une fois (`init({ url })`), les méthodes la
  dérivent (collection / ressource / batch) ;
- les **conversions** sont des fonctions passées une fois (`init({ get,
  create, update, delete })`), surchargeables ponctuellement par appel ;
- le service est bâti sur `HttpService` (cf. [[CommonAngular]]), donc aucune
  duplication de la couche HTTP elle-même.

Résultat côté applicatif : un data-service se réduit à une configuration et
des méthodes d'une ligne.

## Les types génériques

| Type | Rôle | Exemple [[TaskManager]] |
|---|---|---|
| `TFront` | Modèle métier manipulé par les stores/composants | `ITask` (dates en `Date`) |
| `TBack` | DTO réseau renvoyé/attendu par le data-server | `IBackTask` (dates en `string` ISO) |
| `TIdKey` | Nom du champ identifiant, `'id'` par défaut | `'id'`, ou `'uuid'` sur une autre ressource |

La convention `I*` / `IBack*` et la séparation modèle de store / DTO sont
celles déjà en place dans [[Frontend]] (`*-back.model.ts` à côté du
data-service).

## Les adapters

Trois types de fonctions de conversion, tous exportés par la lib :

| Type | Signature | Utilisé par |
|---|---|---|
| `ResAdapter<TFront, TBack>` | `(back: TBack) => TFront` | toutes les lectures + la réponse des écritures |
| `ReqAdapter<TIn, TOut>` | `(input: TIn) => TOut` | corps envoyé en `POST`/`PUT` (`TOut` = `WritePayload<TBack, TIdKey>`) |
| `PageAdapter<TBack, TBackPage>` | `(backPage: TBackPage) => { items: TBack[]; meta: IPageMeta }` | enveloppe de pagination du `GET` collection |

### Résolution en cascade

Pour chaque appel, l'adapter effectif est le premier trouvé dans cet ordre :

1. celui passé dans les **options de l'appel** (surcharge ponctuelle) ;
2. celui configuré par **`init()`** pour cette opération ;
3. un **passthrough** (`back as TFront`), utile quand `TFront` et `TBack`
   ont la même forme et qu'aucune conversion n'est nécessaire.

Les adapters sont donc **tous optionnels** : un backend dont les DTO
correspondent déjà aux modèles front n'a besoin d'aucun adapter.

## Cycle de vie des appels

Chaque méthode applique la même politique avant de renvoyer son observable :

```ts
request$.pipe(take(1), takeUntil(this.destroy$));
```

- **`take(1)`** : une seule réponse par requête, l'observable se termine
  ensuite et libère sa souscription.
- **`takeUntil(destroy$)`**, placé **en dernier** : la destruction du
  propriétaire annule la requête en vol (l'observable se termine sans
  émettre), et un appel *postérieur* à la destruction ne part même pas sur
  le réseau.

### Ce qui déclenche `destroy$`

Le service étant instancié à la main (`new`), Angular n'appelle pas son
`ngOnDestroy` : il faut lui donner une durée de vie. Deux chemins, tous deux
idempotents :

| Chemin | Quand |
|---|---|
| `DestroyRef` passé au constructeur | usage recommandé, instanciation manuelle |
| `ngOnDestroy` | quand le service est fourni par DI (`providers: [RestfulApiService]`) |

```ts
private api = new RestfulApiService<ITask, IBackTask>(
  inject(HttpService),
  inject(DestroyRef),
).init({ url: `${environment.urls.dataServer}/task` });
```

> Sans `DestroyRef` ni fourniture par DI, rien ne complète `destroy$` : les
> requêtes ne sont jamais annulées. C'est pourquoi `inject(DestroyRef)` fait
> partie de la forme recommandée.

Détail d'implémentation : `destroy$` est un `ReplaySubject<void>(1)`, pas un
`Subject`. `takeUntil` ignore la **complétion** de son notifier — avec un
`Subject` déjà complété, un appel postérieur à la destruction serait quand
même parti. Le replay de l'émission coupe ces appels tardifs.

### Ça ne remplace pas le `takeUntilDestroyed` de l'appelant

Le service ne connaît que sa propre durée de vie, pas celle du composant ou
du synchronizer qui s'abonne. La règle de [[Frontend]] reste entière : toute
souscription porte son `takeUntilDestroyed()` ou son `takeUntil(this.destroy$)`
nettoyé en `ngOnDestroy`. Les deux se composent — le service coupe au
niveau de la ressource, l'appelant au niveau de sa vue.

## Configuration — `init()`

```ts
interface IRestfulApiConfig<TFront, TBack, TIdKey = 'id'> {
  url: string;                                  // URL de base, sans slash final
  idKey?: TIdKey;                               // nom du champ identifiant ('id' par défaut)
  get?: ResAdapter<TFront, TBack>;              // getAll / getById / getByIds
  create?: { reqAdapter?; resAdapter? };        // reqAdapter : Omit<TFront, TIdKey> → WritePayload
  update?: { reqAdapter?; resAdapter? };        // reqAdapter : Partial<TFront> → WritePayload (sans id)
  delete?: { resAdapter? };                     // seulement si le backend renvoie la ressource supprimée
}
```

`init()` renvoie `this`, ce qui permet de chaîner à la construction. **Toute
méthode CRUD appelée avant `init({ url })` lève une erreur explicite** plutôt
que de construire une URL invalide silencieusement.

## API

Toutes les méthodes prennent leurs arguments requis d'abord, puis **un seul
objet d'options final**, entièrement optionnel (`resAdapter`, `reqAdapter`,
`pageAdapter`, `query`, plus les `headers`/`params` de `HttpClient`).

| Méthode | Requête | Retour |
|---|---|---|
| `getAll(options?)` | `GET ${url}/` | `Observable<IPageResult<TFront>>` |
| `getById(id, options?)` | `GET ${url}/${id}` | `Observable<TFront>` — id réattaché par le service |
| `getByIds(ids, options?)` | `POST ${url}/batch` avec `{ ids }` | `Observable<TFront[]>` |
| `create(body, options?)` | `POST ${url}/` | `Observable<TFront>` — body sans id |
| `update({ id, ...changes }, options?)` | `PUT ${url}/${id}` | `Observable<TFront>` |
| `remove(id, options?)` | `DELETE ${url}/${id}` | `Observable<IRemoveResult<TFront>>` |

### `getAll` renvoie toujours des métadonnées

`getAll` renvoie **toujours** `{ items, meta }` (`IPageResult<TFront>`), que
l'appel soit paginé ou non — une seule forme de réponse pour un seul
endpoint, comme le font JSON:API et la plupart des API REST. Sans `query`,
aucun query param de pagination n'est envoyé ; c'est le seul changement.

```ts
interface IPageMeta { total: number; page: number; pageSize: number; totalPages: number }
interface IPageResult<TFront> { items: TFront[]; meta: IPageMeta }
```

### Ce que renvoient `create`, `update` et `remove`

Ce que dit la norme HTTP (RFC 9110), et ce que fait le service :

| Verbe | Norme | Service |
|---|---|---|
| `POST` (create) | `201 Created` + header `Location`, body avec la représentation créée | `Observable<TFront>` — la ressource créée (elle porte l'id et les champs générés serveur) |
| `PUT` (update) | `200 OK` **ou** `204 No Content`, les deux conformes | `Observable<TFront>` — la représentation canonique renvoyée par le backend |
| `DELETE` | `204 No Content` (courant), `200 OK` + représentation, ou `202 Accepted` | `Observable<IRemoveResult<TFront>>` — couvre les deux sans union |

```ts
interface IRemoveResult<TFront, TIdKey = 'id'> {
  id: IdOf<TFront, TIdKey>; // toujours présent : écho de l'argument, pas une info serveur
  item?: TFront;       // seulement si le backend a renvoyé la ressource ET qu'un resAdapter delete existe
}
```

`remove` renvoyait auparavant `Observable<TFront | void>`, une union qui
obligeait l'appelant à caster. La forme `{ id, item? }` est stable quel que
soit le backend : sur un `204` on obtient `{ id }`, sur un `200` avec
représentation `{ id, item }`. L'`id` étant toujours là, un synchronizer peut
enchaîner sur la suppression dans le store sans refermer sur l'identifiant.

> `create` et `update` **supposent** que le backend renvoie la
> représentation. C'est le cas des routes actuelles (cf. [[Routes]]) et le
> choix majoritaire, mais la norme autorise un `204` sur `PUT` : contre un
> backend qui ne renvoie rien, le `resAdapter` serait appelé avec une
> réponse vide.

### Le service est seul responsable de l'identifiant

Un id voyage dans l'URL, pas dans le corps. Plutôt que de laisser chaque
appelant appliquer cette règle, le service fait la traduction dans les deux
sens :

| Côté front | Ce que fait le service |
|---|---|
| `update({ id, ...changes })` | extrait l'id → `PUT ${url}/${id}`, envoie le corps **sans** l'id |
| `create(body)` | entrée `Omit<TFront, TIdKey>` : pas d'id, il est généré par le serveur |
| `getById(id)` | tolère une réponse **sans** id et **réattache** celui de l'appel → `TFront` complet |

```ts
this.api.update({ id: '42', title: 'Modifiée' });
// → PUT task/42   body : { title: 'Modifiée' }   (le reqAdapter ne voit même pas l'id)

this.api.getById('42');
// → GET task/42 ; réponse { title: 'Modifiée' } → émet { id: '42', title: 'Modifiée' }
```

Conséquences :

- **Un seul argument pour `update`**, au lieu d'un id + un partial à tenir
  synchronisés. L'id ne peut plus diverger entre l'URL et le corps.
- **Le `reqAdapter` ne voit jamais l'identifiant** : le service l'a retiré
  avant de l'appeler. L'adapter n'a donc aucun moyen de le renvoyer par
  inadvertance, et le corps est typé `WritePayload<TBack, TIdKey>` =
  `Partial<Omit<TBack, TIdKey>>`.
- **`getById` renvoie un `TFront` complet**, directement utilisable par un
  store d'entités indexé par id (`withEntities`, cf. [[Frontend]]) — pas de
  `{ ...task, id }` à refaire à chaque appel. Le backend n'a même pas besoin
  de répéter l'id dans sa réponse ; s'il le fait, c'est celui de l'appel qui
  fait foi, il ne peut pas contredire l'URL demandée.

`getAll` et `getByIds` renvoient à l'inverse des `TFront` **complets tels
que le backend les fournit** : sur une collection, le service ne peut pas
réattacher quoi que ce soit — seul l'id porté par chaque ressource dit
lequel est lequel.

> À noter : « pas d'id dans le corps » est une convention, pas une règle
> RFC — JSON:API impose au contraire l'id dans le body.

### Quand l'identifiant ne s'appelle pas `id`

Le nom du champ identifiant est un paramètre générique (`TIdKey`), `'id'`
par défaut, à déclarer avec la config :

```ts
private api = new RestfulApiService<IDevice, IBackDevice, 'uuid'>(
  inject(HttpService),
  inject(DestroyRef),
).init({
  url: `${environment.urls.dataServer}/device`,
  idKey: 'uuid',
});

this.api.update({ uuid: 'abc', label: 'B' }); // → PUT device/abc   body : { label: 'B' }
```

Sans ce générique, un modèle clé par `uuid` ne compilerait pas : le type
« partial dont l'identifiant est obligatoire » a besoin de connaître le nom
de ce champ.

### `getByIds` passe par POST

Récupérer N ressources par leurs ids via `GET ?ids=1,2,3` bute sur la limite
de longueur d'URL dès que la liste grossit. La méthode fait donc un `POST`
sur une route dédiée (`${url}/batch`) avec `{ ids }` dans le body. Elle
reste **sémantiquement une lecture** : elle utilise le `resAdapter` de `get`,
jamais celui de `create`.

> ⚠️ Aucune route `/batch` n'existe encore sur les backends Rust actuels
> (cf. [[Routes]]) : cette méthode suppose son ajout côté backend.

## Exemples d'implémentation

### 1. Cas minimal — backend aligné sur le modèle front

Aucun adapter : `TFront` et `TBack` ont la même forme, le passthrough suffit.

```ts
@Injectable({ providedIn: 'root' })
export class TagDataService {
  private api = new RestfulApiService<ITag, ITag>(inject(HttpService), inject(DestroyRef)).init({
    url: `${environment.urls.dataServer}/tag`,
  });

  getAll(): Observable<IPageResult<ITag>> {
    return this.api.getAll();
  }

  create(tag: ITag): Observable<ITag> {
    return this.api.create(tag);
  }

  remove(id: string): Observable<IRemoveResult<ITag>> {
    return this.api.remove(id);
  }
}
```

### 2. Cas complet — adapter dédié (style [[TaskManager]])

Le `TaskDataAdapter` existant (`fromBack` / `toBack` / `toBackPartial`) est
simplement branché dans `init()` ; les méthodes du data-service deviennent
des one-liners.

```ts
@Injectable({ providedIn: 'root' })
export class TaskDataService {
  private adapter = inject(TaskDataAdapter);

  private api = new RestfulApiService<ITask, IBackTask>(
    inject(HttpService),
    inject(DestroyRef),
  ).init({
    url: `${environment.urls.dataServer}/task`,
    get: (back) => this.adapter.fromBack(back),
    create: {
      reqAdapter: (task) => this.adapter.toBack(task),
      resAdapter: (back) => this.adapter.fromBack(back),
    },
    update: {
      reqAdapter: (changes) => this.adapter.toBackPartial(changes),
      resAdapter: (back) => this.adapter.fromBack(back),
    },
  });

  getAll(query?: IPageQuery): Observable<IPageResult<ITask>> {
    return this.api.getAll({ query });
  }

  getById(id: string): Observable<ITask> {
    return this.api.getById(id); // ITask complet, id réattaché par le service
  }

  update(changes: UpdatePayload<ITask, 'id'>): Observable<ITask> {
    return this.api.update(changes); // { id, ...champs à modifier }
  }

  delete(id: string): Observable<IRemoveResult<ITask>> {
    return this.api.remove(id);
  }
}
```

> L'ordre des champs compte : `adapter` doit être injecté **avant** `api`,
> puisque les closures passées à `init()` le référencent.

### 3. Pagination, filtres et tri

`query` est sérialisé en query params : `page`, `pageSize`, un paramètre par
entrée de `filters`, et `sort` sous la forme `champ:direction` séparés par
des virgules.

```ts
this.api.getAll({
  query: {
    page: 2,
    pageSize: 20,
    filters: { status: 'todo', archived: false },
    sort: [{ field: 'dueDate', direction: 'asc' }],
  },
});
// → GET task/?page=2&pageSize=20&status=todo&archived=false&sort=dueDate:asc
```

La réponse est normalisée côté front :

```ts
{ items: ITask[], meta: { total: 42, page: 2, pageSize: 20, totalPages: 3 } }
```

### 4. Enveloppe backend différente — `pageAdapter`

Par défaut, `getAll` suppose que le backend renvoie déjà `{ items, meta }`.
Si l'enveloppe diffère, `pageAdapter` fait la traduction — c'est le seul
endroit qui connaît la forme réseau de la pagination.

```ts
interface IBackTaskPage {
  data: IBackTask[];
  totalCount: number;
  currentPage: number;
  perPage: number;
}

const fromBackPage = (page: IBackTaskPage) => ({
  items: page.data,
  meta: {
    total: page.totalCount,
    page: page.currentPage,
    pageSize: page.perPage,
    totalPages: Math.ceil(page.totalCount / page.perPage),
  },
});

getAll(query?: IPageQuery): Observable<IPageResult<ITask>> {
  return this.api.getAll({ pageAdapter: fromBackPage, query });
}
```

### 5. Chargement ciblé par ids

À brancher sur `onLoadIdsChange$` du store d'entités (cf. `loadByIds` /
`addIdToLoad` dans [[Frontend]]) :

```ts
getByIds(ids: string[]): Observable<ITask[]> {
  return this.api.getByIds(ids);
}
// → POST task/batch   body : { ids: ['a', 'b', 'c'] }
```

### 6. Surcharge ponctuelle d'un adapter

Un appel particulier peut ignorer l'adapter configuré, sans toucher à la
configuration globale :

```ts
// Vue « light » : le backend renvoie un DTO allégé sur cette route
this.api.getById(id, { resAdapter: (back) => this.adapter.fromBackSummary(back) });

// Header spécifique à un appel
this.api.getAll({ headers: { 'X-Include-Archived': 'true' } });
```

### 7. Création quand l'id est généré côté backend

`create<TIn>` accepte une forme d'entrée différente de `TFront` (ici sans
`id`). Dans ce cas, l'adapter configuré par `init({ create })` — typé pour
`TFront` — ne correspond plus : il faut passer le `reqAdapter` explicitement.

```ts
create(task: Omit<ITask, 'id'>): Observable<ITask> {
  return this.api.create(task, { reqAdapter: (t) => this.adapter.toBack(t) });
}
```

### 8. Branchement dans un synchronizer NgRx

Le découpage de [[Frontend]] reste inchangé : les composants parlent aux
stores, les synchronizers parlent au réseau — `RestfulApiService` vit
uniquement **sous** le data-service.

```ts
private tasksHandle(): void {
  const events = this.tasksStore.getEvents();

  events.onLoadRequest$
    .pipe(
      exhaustMap(() => this.taskData.getAll()),
      takeUntil(this.destroy$),
    )
    .subscribe((page) => this.tasksStore.set(page.items));

  events.onUpdate$
    .pipe(
      mergeMap(({ id, changes }) => this.taskData.update({ id, ...changes })),
      takeUntil(this.destroy$),
    )
    .subscribe((task) => this.tasksStore.update_withoutStore(task.id, task));
}
```

## Pourquoi pas un singleton `providedIn: 'root'`

`init()` stocke un état (URL + adapters) **par instance**. Or les types
génériques TypeScript sont effacés à l'exécution : un service
`providedIn: 'root'` ne donnerait qu'**une seule instance** partagée entre
toutes les ressources — le `init()` des tâches écraserait celui des
catégories.

La classe est donc décorée `@Injectable()` **sans** `providedIn`, et chaque
data-service construit sa propre instance :

```ts
private api = new RestfulApiService<ITask, IBackTask>(inject(HttpService)).init({ ... });
```

C'est aussi pourquoi `HttpService` est passé au constructeur au lieu d'un
`inject()` en champ : l'instanciation manuelle peut avoir lieu hors contexte
d'injection (notamment dans les tests), où `inject()` échouerait (NG0203).
Une dérogation ESLint commentée couvre ce choix dans le fichier.

## Conventions d'URL attendues côté backend

Avec `init({ url: 'https://api.exemple/task' })` :

| Opération | Requête |
|---|---|
| `getAll` | `GET https://api.exemple/task/` |
| `create` | `POST https://api.exemple/task/` |
| `getById` | `GET https://api.exemple/task/{id}` |
| `update` | `PUT https://api.exemple/task/{id}` |
| `remove` | `DELETE https://api.exemple/task/{id}` |
| `getByIds` | `POST https://api.exemple/task/batch` |

Le slash final sur la collection et son absence sur la ressource reprennent
les conventions déjà en place côté data-server (cf. [[Routes]]). Une route
qui sort de ce schéma (ex. `GET /task/{id}/history`) n'est pas du CRUD de
cette ressource : elle relève d'un data-service dédié, avec sa propre
instance et sa propre URL de base.

## Tests

`restful-api.service.spec.ts` couvre les deux modes de configuration (URL
seule avec passthrough, et URL + adapters par opération), la surcharge
ponctuelle par options, la sérialisation des query params, l'adaptation
d'une enveloppe backend différente, le batch-get, l'erreur levée quand
`init({ url })` n'a pas été appelé, et le cycle de vie (complétion après une
émission, annulation via `DestroyRef` et via `ngOnDestroy`, appel tardif qui
ne part pas). Le service est instancié directement
(`new RestfulApiService(httpService)`), conformément à son usage réel, avec
`HttpTestingController` pour les requêtes — `verify({ ignoreCancelled: true })`
puisque les tests de destruction laissent volontairement une requête annulée.

## Liens

- [[CommonAngular]] — la librairie qui héberge le service
- [[Frontend]] — data-services, adapters et synchronizers côté [[TaskManager]]
- [[Routes]] — routes réellement exposées par le backend Rust
