#taskmanager #routes

Table complète des routes du projet [[TaskManager]] : [[Frontend]] (Angular
Router) et [[Backend]] (Axum HTTP).

---

## Routes front (Angular)

Déclarées dans `src/app/app.routes.ts`, toutes **lazy-loadées**
(`loadChildren`) sauf la redirection racine. Toutes les features sauf
`login`/`register`/`server-error` sont protégées par `authGuard`.

| Route | Garde | Composant / enfants | Notes |
|---|---|---|---|
| `/login` | — | `LoginPageComponent` | Header masqué |
| `/register` | — | `RegisterPageComponent` | Header masqué |
| `/server-error` | — | `ServerErrorPageComponent` | Header masqué (backend injoignable) |
| `` (racine) | `rootRedirectGuard` | — | Redirige selon l'état d'auth |
| `/chrono/list` | `authGuard` | `ChronoListPageComponent` | Liste des chronos actifs (QUE-155), header standard avec bouton retour vers `/task/list` |
| `/chrono/:id` | `authGuard` | `ChronoPageComponent` | Header masqué ; page **non verrouillée** (multitâche) — déclarée après `/chrono/list` pour ne pas être capturée par `:id` |
| `/task/list` | `authGuard` | `TaskListPageComponent` | Liste des tâches |
| `/task/calendar` | `authGuard` | `TaskCalendarPageComponent` | Vue calendrier (grille + agenda) |
| `/task/archive` | `authGuard` | `TaskArchivePageComponent` | Tâches archivées |
| `/task/details` | `authGuard` | `TaskDetailPageComponent` | Création d'une tâche |
| `/task/details/:id` | `authGuard` | `TaskDetailPageComponent` | Édition / consultation d'une tâche |
| `/task/manage` | `authGuard` | `ManageTaskPageComponent` | Post-création/édition (retour liste) |
| `/task/edit` | `authGuard` | — | `redirectTo: 'details'` (alias legacy) |
| `/category/list` | `authGuard` | `CategoryListPageComponent` | Liste des catégories |
| `/category/edit` | `authGuard` | `EditCategoryPageComponent` | Création (bouton retour → `/category/list`) |
| `/category/edit/:id` | `authGuard` | `EditCategoryPageComponent` | Édition |
| `/user` | `authGuard` | `UserPageComponent` | Compte utilisateur (bouton retour → `/task/list`) |

`authGuard` redirige vers `/login` si `AuthService.isAuth()` (JWT valide)
est faux.

## Routes backend (Rust/Axum)

Trois `Router` empilés dans `main.rs` (`free.merge(token).merge(protected)`),
détail des groupes dans [[Backend]]#Authentification — 3 groupes de routes.

### Libre (`free`) — aucune authentification

| Méthode | Route | Handler | Description |
|---|---|---|---|
| `POST` | `/token` | `verify_hash` | Délivre le token applicatif `X-Token` |
| `POST` | `/logout` | `logout` | Déconnexion |
| `GET` | `/calendar/{token}` | `calendar_feed::feed` | Flux ICS (QUE-146) — protégé par le jeton opaque de l'URL, pas par un header |

### Groupe « Token » (`X-Token` seul)

| Méthode | Route | Handler | Description |
|---|---|---|---|
| `POST` | `/auth` | `users::auth` | Connexion — renvoie un JWT |
| `POST` | `/register` | `users::register` | Inscription |
| `GET` | `/register/available/{username}` | `check_username_available` | Disponibilité d'un nom d'utilisateur |
| `GET` | `/register/available-email/{email}` | `check_email_available` | Disponibilité d'un email |
| `GET` | `/user/id/{user_id}` | `get_user` | Infos publiques d'un utilisateur par id |

### Groupe « Protégé » (`X-Token` + JWT)

| Méthode | Route | Handler | Description |
|---|---|---|---|
| `GET`/`POST` | `/persistence` | `persistence::{get,set}_persistence` | Persistance chiffrée générique par utilisateur |
| `GET` | `/user/` | `get_current_user` | Utilisateur courant (déduit du JWT) |
| `DELETE` | `/user/` | `delete_account` | Suppression du compte |
| `POST` | `/user/refresh` | `refresh_token` | Rafraîchit le JWT (évite la reconnexion à chaque réouverture, QUE-93) |
| `POST` | `/user/calendar-token` | `regenerate_calendar_token` | Régénère le jeton opaque du flux ICS |
| `GET`/`POST` | `/task/` | `task::{get_all,create}` | Liste / création d'une tâche |
| `GET`/`DELETE`/`PUT` | `/task/{id}` | `task::{get_by_id,delete,update}` | Détail / suppression / mise à jour d'une tâche — `update` calcule et renvoie la tâche canonique (`next_due_date`, `done_summary`…) |
| `GET` | `/task/{id}/history` | `task::get_history` | Historique paginé (done/postpone) d'une tâche |
| `GET`/`POST` | `/category/` | `category::{get_all,create}` | Liste / création d'une catégorie |
| `PUT`/`DELETE` | `/category/{id}` | `category::{update,delete}` | Mise à jour / suppression |
| `GET` | `/task-history/done` | `task_history::get_done_in_range` | Réalisations dans une plage (`?from=&to=`, QUE-138) |
| `DELETE` | `/task-history/done/{id}` | `task_history::delete_done` | Supprime une entrée de réalisation |
| `DELETE` | `/task-history/postpone/{id}` | `task_history::delete_postpone` | Supprime une entrée de report |
| `GET` | `/stats/overview` | `stats::overview` | Vue d'ensemble (retard, dette de temps…) |
| `GET` | `/stats/history` | `stats::history` | Historique bucketé jour/semaine/mois (QUE-46) |
| `GET` | `/stats/category-history` | `stats::category_history` | Idem, par tâche |
| `GET` | `/stats/time-by-category` | `stats::time_by_category` | Temps passé par catégorie (période + navigation) |
| `GET` | `/stats/time-history` | `stats::time_history` | Courbe d'activité (temps passé), filtrable par tâche |

### CORS

`allow_credentials(true)` + origines explicites (`CORS_ORIGIN`, liste
séparée par des virgules) ou `*` → dans ce dernier cas, `mirror_request()`
renvoie l'origine du requêteur (un `*` littéral avec credentials est
interdit par la spec HTTP).

## Liens
- [[TaskManager]]
- [[Frontend]]
- [[Backend]]
- [[Modèle de données]]
- [[Récurrence]]
