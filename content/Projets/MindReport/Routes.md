#mindreport #routes

Table complète des routes Angular du projet [[MindReport]] (pas de backend,
donc pas de routes HTTP — cf. [[MindReport]]#Persistance — pas de backend,
`localStorage` seul).

---

## Routes racine (`src/app/app.routes.ts`)

Toutes lazy-loadées (`loadChildren`/`loadComponent`) sauf les redirections.
**Aucun guard d'authentification** (pas de notion de compte) — seul
`/logs` est gardé, par une condition de configuration statique
(`LogsGuard`).

| Route | Garde | Cible | Notes |
|---|---|---|---|
| `` (racine) | — | — | `redirectTo: 'dashboard'` |
| `/dashboard` | — | `dashboard/routes.ts` | Page d'accueil, widgets configurables |
| `/daily` | — | `daily/routes.ts` | Saisie quotidienne |
| `/config` | — | `config/routes.ts` | Configuration des items suivis |
| `/history` | — | `history/routes.ts` | Historique des saisies |
| `/datamanager` | — | `DataManagerPageComponent` | Import/export JSON (composant unique, pas de sous-routes) |
| `/splash` | — | `SplashScreenPageComponent` | Écran de chargement initial (redirection post-boot via `redirectTo` en query param) |
| `/logs` | `LogsGuard` | `logs/routes.ts` | Journal applicatif — accessible seulement si `config.json.logs === true` |
| `/home` | — | — | `redirectTo: 'daily'` (alias legacy) |
| `**` | — | — | `redirectTo: 'home'` |

`LogsGuard` (`guard/logs.guard.ts`) : lit `ConfigService.config$` (config
statique `assets/config/config.json`, pas la config utilisateur) et
redirige vers `/` si `logs` est absent/`false` — pas de logique
d'authentification, juste un flag de build/déploiement.

## Sous-routes par feature

### `dashboard/routes.ts`
| Route | Composant |
|---|---|
| `` | `DashboardPageComponent` |

### `daily/routes.ts`
| Route | Composant |
|---|---|
| `` | `DailyPageComponent` |

Pas de paramètre de date dans l'URL : la date affichée est un état interne
du composant (navigation par flèches précédent/suivant, pas de deep-link
vers un jour précis).

### `config/routes.ts`
| Route | Composant | Notes |
|---|---|---|
| `` | `ConfigPageComponent` | Liste des items configurés |
| `daily-item/new` | `DailyItemPageComponent` | Création d'un item |
| `daily-item/edit/:id` | `DailyItemPageComponent` | Édition d'un item existant |

### `history/routes.ts`
| Route | Composant |
|---|---|
| `` | `HistoryPageComponent` |

### `logs/routes.ts`
| Route | Composant | Notes |
|---|---|---|
| `` | `LogsPageComponent` | Activation/désactivation, purge des logs |
| `display` | `LogsDisplayPageComponent` | Consultation du contenu des logs stockés |

## Routes sans sous-fichier (`loadComponent` direct)

Déclarées directement dans `app.routes.ts`, pas de fichier `routes.ts`
dédié (features à une seule page) :

- `/datamanager` → `DataManagerPageComponent`
  (`components/data-manager/page/data-manager/`)
- `/splash` → `SplashScreenPageComponent`
  (`components/splash/page/splash-screen/`)

## Liens
- [[MindReport]]
- [[Modèle de données]]
