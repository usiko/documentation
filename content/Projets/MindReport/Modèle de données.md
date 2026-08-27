#mindreport #localstorage #jsonschema

Modèle de données du projet [[MindReport]] — stocké intégralement dans le
`localStorage` du navigateur (pas de base distante, cf. [[MindReport]]
#Persistance — pas de backend, `localStorage` seul), validé/réparé via
`jsonschema` (`MindDataAdapterService`).

---

## Clés `localStorage`

Préfixe commun `MREPORT_` (`StorageService`) :

| Clé | Contenu |
|---|---|
| `MREPORT_config` | `IConfig` — items suivis + seuils |
| `MREPORT_DAILYITEM_<id>` | `IDailyEntity` — une entrée par jour (`id` = `YYYY-MM-DD`, ou `YYYY-MM-DD_DRAFT` pour un brouillon) |
| `MREPORT_LOG_` | `IStorageLogsObj` — activation + liste des logs applicatifs |

Chaque valeur stockée est enveloppée `{ version: number, data: T }` — le
`version` correspond au `dataVersion` de la config statique
(`assets/config/config.json`) au moment de l'écriture (cf. §Migration).

### Ancien format (v0), migré automatiquement

Avant la clé unique par entité, tout vivait sous une seule clé
`mindReport` (`IDailyDataBase { dailyItems, config, version }`).
`StorageService.init()` détecte ce cas (`handleOldStorage`, déclenché si
`dataVersion === 1`) et éclate les données vers le nouveau format
(`setDaily`/`setConfig` par entité), puis supprime l'ancienne clé.

## `IDailyEntity` (une entrée quotidienne)

```ts
interface IDaily {
  id?: string;
  others: IOtherData[];
  state: 'sent' | 'draft';
  dailyDate: string;       // date représentée (ISO)
  creationDate: string;    // ISO
  modificationDate: string; // ISO
  fixedDate?: string;      // horodatage de la dernière réparation auto, si applicable
  logs: string[];          // traces de réparation appliquées à cette entrée
}
interface IDailyEntity extends IDaily { id: string }
```

- `id` = clé de stockage dérivée de la date (`YYYY-MM-DD`), ou suffixée
  `_DRAFT` pour la version brouillon du même jour — **deux entités
  distinctes en storage** pour un même jour tant qu'un brouillon existe.
  `MindReportStore.getDailyByDate` renvoie le brouillon en priorité s'il
  existe, sinon la version envoyée.
- Un brouillon envoyé (`setDailyFromDate` avec `state !== 'draft'`)
  supprime automatiquement le brouillon associé (`removeDraftFromDate`).
- `logs: string[]` ici est un **journal de réparation par entité**
  (« fixed creation date », « fixed item energy »...), à ne pas confondre
  avec le store applicatif `LogStore`/`IStorageLog` (journal global de
  l'app, cf. `MindReport.md`#Fonctionnalités).

### `IOtherData` (une valeur d'indicateur, dans `IDaily.others[]`)

```ts
interface IReport {
  value: number;
  comment?: string;
}
interface IOtherData {
  value: IReport;
  timeInterval?: {
    startTime: { hours: number; minutes: number };
    endTime: { hours: number; minutes: number };
  };
  itemId: string; // référence IDailyOtherItemConfig.id
}
```

Un item peut porter une **valeur numérique** (`value.value` + commentaire
optionnel) et/ou une **plage horaire** (`timeInterval`), selon ce que son
`IDailyOtherItemConfig.valuesOption` autorise. Le store `DailyItemsStore`
(entités séparées de `MindReportStore`, jointes par `dailyId`) gère ces
valeurs indépendamment du reste de l'entrée quotidienne — permet des mises
à jour granulaires (`updateOtherValueById`) sans réécrire toute l'entrée.

## `IConfig` (config utilisateur, persistée)

```ts
interface IConfig {
  dailyItems: IDailyOtherItemConfig[];
  thresholds: INumberThreshold[];
}
interface IDailyOtherItemConfig {
  id: string;
  name: string;
  required: boolean;
  order?: number;          // ordre dans la liste de config / saisie
  dashboardOrder?: number; // présence + ordre sur le dashboard (undefined = absent du dashboard)
  icon?: string;
  displayMode: 'badge' | 'circle';
  valuesOption: {
    number?: IDailyItemNumberConfig;      // { min, max, step, unit?, defaultValue? }
    timeInterval?: IDailyItemTimeIntervalConfig; // { startTime, endTime }
  };
  thresholds?: INumberThreshold[]; // dénormalisé pour l'export, source de vérité = ThresholdsStore
}
```

- Un item peut définir `number` seul, `timeInterval` seul, ou les deux
  (ex. le sommeil migré depuis l'ancien modèle : durée **et** plage
  horaire).
- `dashboardOrder` distinct de `order` : un item peut être configuré
  (visible dans `/config` et en saisie) sans apparaître sur le dashboard.

### `INumberThreshold` (seuils de couleur, `ThresholdsStore`)

```ts
interface INumberThreshold {
  id: string;
  label: string;
  value: number;   // borne basse du palier
  color: string;
  configId: string; // item associé
}
```

Store d'entités **séparé** de `ConfigDailyItemStore`, joint par
`configId` — un item « plein » (`fullEntities`, exposé au reste de l'app)
est reconstruit en combinant `IDailyOtherItemConfig` + ses
`INumberThreshold[]`. La couleur affichée pour une valeur donnée n'est
**jamais un palier brut** : `getThresholdNumberValueByConfigId` interpole
(`chroma.mix(..., 'lrgb')`) entre les deux seuils encadrants — en dessous
du premier ou au-dessus du dernier seuil, couleur du seuil le plus proche
sans interpolation.

## `IAppConfig` (config statique, `assets/config/config.json`, non modifiable en runtime)

```ts
interface IAppConfig {
  logs: boolean;             // active la feature /logs (cf. LogsGuard)
  displayAppVersion: string;
  dataVersion: number;       // pilote StorageService.handleOldStorage
  daily: { others: IConfigItem };            // bornes par défaut d'un nouvel item
  config: {
    defaultEnergy: IConfigItem;               // valeurs par défaut migration v0 "energy"
    defaultSleeping: IConfigItem & { startTime; endTime };
  };
  itemIcons: { id: string; tags: string[]; name: string; lucidIcon: string }[]; // catalogue du sélecteur d'icône
}
```

Chargée une fois au boot (`ConfigService.load()`, `HttpClient` sur un
fichier statique — **pas un appel réseau vers un serveur applicatif**),
avant l'initialisation du synchronizer.

## Validation et réparation (`MindDataAdapterService`)

Toute donnée lue depuis (ou écrite vers) le storage passe par un schéma
JSON (`jsonschema`, pas AJV contrairement à [[CommonAngular]]/
[[TaskManager]]) :

- **Lecture** (`toStorageDaily`/`toStorageConfig`) : si la donnée brute ne
  respecte pas le schéma, tentative de **réparation** (`fixDaily`/
  `fixConfig`) plutôt qu'une erreur bloquante — ex. dates manquantes
  complétées (`creationDate`, `modificationDate`, `dailyDate` extraite de
  l'`id` via regex `\d{4}-\d{2}-\d{2}`), `state` par défaut à `'sent'`,
  anciens champs `energy`/`sleeping` (format v0, avant le modèle générique
  `others[]`) convertis en `IOtherData` avec `itemId: 'energy'`/`'sleep'`.
  La réparation réussie est immédiatement **réécrite en storage**
  (`fixed: true` → `setDaily`) et tracée dans `IDaily.logs`.
- **Écriture** (`toStorage`) : refuse d'écrire sans `dataVersion` connu
  (config statique non chargée) → `throwError('invalid data')`.
- Si la réparation elle-même produit une donnée toujours invalide selon le
  schéma, l'erreur remonte sans écriture (pas de donnée corrompue
  persistée).

## Migration de version (`StorageService.handleOldStorage`)

Un seul cas géré à ce jour : `version === 1` → migration du format
« clé unique » vers « une clé par entité » (cf. §Ancien format (v0)).
Pas de mécanisme de migration incrémentale au-delà (`switch` avec un seul
`case`) — toute évolution future du schéma de stockage devrait suivre le
même schéma (nouveau `case`, incrément de `dataVersion` dans
`config.json`).

## Liens
- [[MindReport]]
- [[Routes]]
