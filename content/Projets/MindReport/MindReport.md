#projet #mindreport #angular #ionic #abandonné

Application de suivi quotidien (« daily ») de données personnelles libres —
énergie, sommeil, humeur, ou tout autre indicateur numérique/plage horaire
configurable par l'utilisateur —, avec dashboard, historique et export/import
JSON. Dépôt unique : `usiko/mind-report` (pas de backend séparé, cf.
§Persistance). Voir aussi [[Routes]] et [[Modèle de données]].

---

> [!warning] Projet abandonné
> Ce projet est **abandonné** au profit d'une réécriture complète, en
> repartant de l'architecture de [[TaskManager]] (Angular standalone + NgRx
> Signals + découpage page/smart/dumb, cf. [[TaskManager/Frontend|Frontend]])
> plutôt que de continuer à faire évoluer cette base. Cette note documente
> l'état du projet **au moment de l'abandon**, pour référence (fonctionnalités
> à reprendre, pièges à éviter côté modèle de données/stockage).

## But

Remplacer un carnet/tableur de suivi personnel (humeur, sommeil, énergie,
habitudes...) par une app mobile/PWA : saisie quotidienne rapide,
dashboard de widgets configurables, historique, seuils de couleur
(codage visuel des valeurs), export/import JSON pour sauvegarde manuelle.
Usage perso, sans compte ni synchronisation multi-appareil.

## Fonctionnalités

- **Saisie quotidienne** (`/daily`) — un item « other » par indicateur
  configuré (valeur numérique et/ou plage horaire), plus commentaire libre.
  Sauvegarde en **brouillon** (`state: 'draft'`) ou **envoyée**
  (`state: 'sent'`) ; un brouillon existant prime sur l'entrée envoyée du
  jour à l'affichage.
- **Dashboard** (`/dashboard`) — widgets pour les items marqués
  `dashboardOrder`, avec valeur du jour et navigation date/heure.
- **Configuration des items** (`/config`) — CRUD des indicateurs suivis
  (`daily-item/new`, `daily-item/edit/:id`) : nom, icône (sélecteur dédié),
  mode d'affichage (`badge`/`circle`), option valeur numérique
  (min/max/step/unité) et/ou plage horaire, ordre d'affichage, seuils de
  couleur.
- **Seuils de couleur** (`INumberThreshold`) — par item, une liste de paliers
  valeur→couleur avec **interpolation** (`chroma-js`, espace `lrgb`) pour
  une couleur dégradée continue plutôt qu'un simple code couleur par palier.
- **Historique** (`/history`) — liste paginée/scroll infini des entrées
  passées, filtrable par item (`loadDailiesByConfig`), détection des jours
  sans saisie (`missing-days`).
- **Import/export JSON** (`/datamanager`) — export de toutes les données
  (ou filtré par état `sent`/`draft`) en fichier `.json` téléchargeable,
  import depuis un fichier avec validation/réparation automatique du schéma
  (cf. [[Modèle de données]]#Validation et réparation).
- **Logs applicatifs** (`/logs`, activable via `config.json`) — journal
  d'évènements internes (succès/erreurs storage) stocké en local, activable/
  désactivable, exportable en JSON, purgeable. Accès protégé par
  `LogsGuard` (redirige si `logs: false` dans la config statique).
- **PWA** — `@angular/service-worker` (`ngsw-config.json`), manifeste +
  icônes (`public/manifest.webmanifest`), installable.

## Stack technique

- **Angular 19** standalone (`signal`/`computed`/`effect`, `input()`/
  `output()`), pas de `NgModule`.
- **Ionic 8** (`@ionic/angular`) pour l'UI + **Capacitor 6** (build natif
  configuré mais app publiée en pratique comme PWA/web app).
- **NgRx Signals** (`@ngrx/signals` v19, `signalStore`, `withEntities`) pour
  l'état — mêmes briques que [[TaskManager]] mais sans `createEntityMethods`
  générique (chaque store réimplémente `add`/`update`/`remove`/`set`).
- **Angular Material** non utilisé ; composants tiers ponctuels :
  `ngx-gauge`/`ng-circle-progress` (jauges dashboard), `@dhutaryan/ngx-mat-timepicker`
  (sélecteur d'heure), `lucide-angular` + `ionicons` (icônes, via un service
  `IconService` dédié).
- **`jsonschema`** — validation JSON Schema (pas AJV) du modèle stocké, avec
  logique de réparation associée (`MindDataAdapterService`).
- **`chroma-js`** — interpolation de couleur pour les seuils.
- **`moment` / `moment-timezone`** — manipulation de dates.
- **TypeScript strict** (`strict`, `noImplicitOverride`,
  `noPropertyAccessFromIndexSignature`, `noImplicitReturns`,
  `noFallthroughCasesInSwitch`).
- **Tests** : Karma/Jasmine (`karma.conf.js`, `.spec.ts` classiques) — *pas*
  migré vers Vitest, contrairement à [[TaskManager]]/[[MongoManager]].
- **ESLint 8** (config `.eslintrc.json` classique, pas flat config) +
  Prettier + Husky/lint-staged (`prepare: husky`, hook `pre-commit`).
- Alias de chemins TS (`@cpn-*`, `@services/*`, `@app-ngrx/*`) définis dans
  `tsconfig.json`, un préfixe par feature de `src/app/components/`.

## Architecture — découpage par feature (page/smart/dumb)

Même principe que [[TaskManager]] (cf.
[[TaskManager/Frontend|Frontend]]#Architecture — découpage par feature),
un dossier par feature sous `src/app/components/` (`dashboard`, `daily`,
`config`, `history`, `logs`, `data-manager`, `splash`, `modal`, `shared`),
chacun avec ses propres `page/`, `smart/`, `dumb/` (nommage incohérent selon
les features : `dumb` **et** `dump` coexistent dans `config/`, `dumbs` dans
`shared/` — pas de convention strictement appliquée, contrairement à
TaskManager).

- **`page`** — reçoit les routes (`app.routes.ts`, `<feature>/routes.ts`),
  compose le chrome partagé via `PageComponent` (`shared/smarts/page`).
- **`smart`** — orchestration, injection des stores.
- **`dumb`/`dump`/`dumbs`** — affichage pur, réutilisable
  (`shared/dumbs/*` : `ui-circle`, `color-choice`, `time-picker`,
  `reorder`/`reorder-grid`, `number-value-display`...).

## Persistance — pas de backend, `localStorage` seul

**Différence structurelle majeure avec [[TaskManager]]/[[MongoManager]]** :
aucune API HTTP, aucune base de données distante. Toute la donnée vit dans
le `localStorage` du navigateur (`StorageService`), avec une clé par
entité (préfixes `MREPORT_`, `MREPORT_DAILYITEM_<id>`, `MREPORT_LOG_`) —
pas de clé unique fourre-tout comme dans l'ancien format v0
(cf. §Migration). Conséquences :

- **Aucune synchronisation multi-appareil** : les données sont propres au
  navigateur/appareil, seul l'export/import JSON manuel permet de les
  déplacer.
- Le rôle habituellement tenu par le *synchronizer* réseau ([[TaskManager]])
  est ici tenu par `SynchronizerService` (`src/app/synchronizer/`), qui
  fait le pont entre les stores NgRx (subjects `addDaily$`/`updateDaily$`/
  `removeDaily$`/`getDailies$`...) et `StorageService` (lecture/écriture
  `localStorage`) — même pattern événementiel, cible différente (storage
  local au lieu d'un backend HTTP).
- Sur les mises à jour d'une même entrée (`updateDaily$`), un `groupBy(id)`
  + `debounceTime(750)` évite d'écrire à chaque frappe ; contrairement au
  `groupBy` + `concatMap` de TaskManager (cf.
  [[TaskManager/Récurrence|Récurrence]]#Bug corrigé), ici c'est un
  *debounce* : la dernière valeur après 750 ms d'inactivité est celle
  persistée, pas une garantie d'ordre strict.

### Configuration statique vs configuration utilisateur

Deux notions de « config » distinctes, à ne pas confondre :

- **`assets/config/config.json`** (`ConfigService`, `IAppConfig`) — chargée
  au démarrage via `HttpClient` (fichier statique servi par le build, pas
  une route API), fixe pour un déploiement donné : activation des logs,
  version d'affichage, version du schéma de données (`dataVersion`, pilote
  les migrations, cf. [[Modèle de données]]#Migration), bornes par défaut
  des items, catalogue d'icônes disponibles (`itemIcons`).
- **Config utilisateur** (`ConfigStore`/`IConfig`, persistée en
  `localStorage`) — la liste des items suivis (`IDailyOtherItemConfig[]`)
  et leurs seuils, modifiable depuis `/config` par l'utilisateur.

## Déploiement

- **Build** : `ng build` (Angular CLI), sortie dans `www/browser` (nom du
  dossier hérité d'un starter Ionic/Capacitor).
- **Serveur** : petit serveur **Express** (`server/server.js`) qui sert le
  build statique — pas de logique métier côté serveur, aucune route API.
- **Heroku** : `Procfile` → `web: npm run server` (port lu depuis
  `process.env.PORT`).
- **Capacitor** configuré (`capacitor.config.ts`, `appId:
  io.ionic.starter` — jamais renommé) mais aucune preuve d'un build natif
  publié ; l'usage réel semble être PWA/web uniquement.

## Points faibles identifiés (contexte de la réécriture)

- **Pas de backend** : pas de synchronisation multi-appareil, pas de
  sauvegarde automatique hors export manuel — motivation probable pour
  repartir sur l'architecture front+API de [[TaskManager]].
  `capacitor.config.ts` avec un `appId` par défaut jamais personnalisé.
- **Historique de migrations de schéma en dur dans le code** — la logique
  de « fix » (`MindDataAdapterService.fixConfig`/`fixDaily`) porte encore
  la migration de champs `energy`/`sleeping` **spécifiques au domaine
  d'origine** (v0/v1) vers le modèle générique `others[]`, du code mort en
  commentaire (`// old to remove`, `// [FIRST MIGRATION]`) jamais nettoyé.
- **Convention de dossiers incohérente** (`dumb` vs `dump` vs `dumbs`),
  contrairement à la convention stricte de [[TaskManager]].
- **Tests non migrés vers Vitest** (Karma encore en place), builder de
  test différent des projets plus récents.
- Voir aussi le fichier `TODO` du dépôt (bugs connus non triés au moment de
  l'abandon : persistance de note entre jours, migration `energy`/`sleeping`
  incomplète pour certains items, perte de seuils à la migration).

## Liens
- [[Routes]]
- [[Modèle de données]]
- [[TaskManager]] — architecture de référence pour la réécriture
