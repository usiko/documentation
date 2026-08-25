#taskmanager #rust #axum #mongodb

Back du projet [[TaskManager]] (dépôt `TaskManager-backend`). Le front est
un dépôt Angular séparé ([[Frontend]]). Voir [[Routes]] pour la table
complète des routes HTTP et leurs groupes d'authentification.

---

## Stack

- **Axum** pour le routing HTTP, driver officiel **`mongodb`** pour la
  persistance, JWT via `axum_jwt`/`Claims`.
- Rust édition 2024, paquet Cargo `webserver` (nom du binaire), déployé sur
  **Heroku** (`Procfile` : `web: ./target/release/webserver`, port lu depuis
  la variable `PORT`).
- **MongoDB Atlas** (une seule base applicative).

## Architecture — 3 couches

- **Modèles** — `src/model/*_model.rs` : structures Mongo + DTO HTTP.
- **Accès DB** — `src/db/*.rs` : requêtes Mongo (un fichier par
  collection/domaine : `task.rs`, `task_history.rs`, `category.rs`,
  `user.rs`, `stats.rs`, `persistence.rs`).
- **Handlers HTTP** — `src/routes/*.rs` : un handler par endpoint, assemble
  la réponse à partir des couches `db`/`utils`.
- **Logique métier pure** — `src/utils/` (ex. `schedule.rs`, le moteur de
  récurrence, cf. [[Récurrence]]) : hors `model`/`db`, testée
  unitairement (`#[cfg(test)]`).

### Convention modèle DB vs DTO HTTP

Un type utilisé à la fois pour la persistance Mongo (`to_document`,
`Collection<T>`) et pour une réponse HTTP **ne doit jamais** porter un
`#[serde(skip_serializing)]` global sur un champ interne (ex. `userId`) :
ça désactive la sérialisation pour **tout** appel `Serialize`, y compris
`to_document` côté DB, pas seulement la réponse JSON HTTP (cf.
`Task`/`TaskDto` dans `task_model.rs`, et `Category`/`CategoryDto`).

- Le modèle DB (`Task`, `Category`…) sérialise **tous** ses champs, y
  compris `userId`.
- Un DTO dédié (`TaskDto`, `CategoryDto`…), avec `From<Modèle> for Dto`,
  omet les champs internes — c'est lui qui est réellement renvoyé
  (`Json(dto)`).
- `skip_serializing`/`skip_serializing_if` sur le modèle DB réservé aux
  champs qui ne doivent **jamais** être persistés, pas à ceux à cacher
  seulement du front.

## Authentification — 3 groupes de routes

Empilés via des `Router` Axum séparés dans `main.rs`, fusionnés
(`free.merge(token).merge(protected)`) :

| Groupe | Middleware(s) | Vérifie |
|---|---|---|
| **Libre** (`free`) | aucun | — |
| **Token** (`token`) | `verify_token_middleware` | Header `X-Token` (HMAC, obtenu via `POST /token`) |
| **Protégé** (`protected`) | `verify_token_middleware` **+** `verify_jwt_middleware` | `X-Token` **et** `Authorization: Bearer <JWT>` |

`verify_token_middleware`/`verify_jwt_middleware` peuvent être désactivés en
dev via `MOCK_TOKEN`/`MOCK_AUTH` (variables d'env, affichent un avertissement
au démarrage). Table complète des routes : [[Routes]].

## Modèle de données

Détail des champs dans [[Modèle de données]]. Résumé des collections
Mongo :

- `tasks` — tâches (titre, description, étapes, échéance, récurrence,
  durée estimée, catégorie, `disabled`/`archived`, `icsExport`, `offset`
  cumulé des reports).
- `category` — catégories (nom, couleur, icône, mot-clé calendrier par
  défaut).
- `task-history-done` / `task-history-postpone` / `task-history-archive` /
  `task-history-inprogress` — historiques (réalisation, report, archivage,
  sessions de chrono), toujours conservés (jamais de suppression physique
  d'une réalisation, seulement `cancelled: true`).

## Calcul dérivé, jamais stocké

`next_due_date`, `done_summary`, `time_spent`, `active_chrono` ne sont
**jamais** persistés sur la tâche : recalculés à chaque réponse HTTP à
partir de l'historique (`utils::schedule::compute_next_due_date`,
`TaskDoneSummary::from_done`, `TaskTimeSpent::compute`). Voir
[[Récurrence]] pour le détail de `compute_next_due_date`.

## Flux calendrier ICS (QUE-146)

`GET /calendar/{token}.ics` (route **libre**, aucun middleware — les
clients calendrier natifs ne savent pas envoyer `X-Token`/`Authorization`) :
protégée par un jeton opaque dans l'URL (`db::user::get_id_by_calendar_token`).
Réutilise `utils::schedule::project_occurrences` (boucle sur
`compute_next_due_date`) plutôt que de dupliquer la logique en `RRULE` ICS —
un mapping RRULE serait fragile pour la récurrence `custom` (motif
**flottant**, calé sur la réalisation réelle, pas une grille fixe).
Évènements en journée entière (QUE-149, pas de notion d'heure de tâche),
filtrable par tâche/catégorie (`?taskId=`/`?categoryId=`), exclusion opt-in
par tâche (`Task.icsExport`).

## Statistiques (`/stats/*`)

- `GET /stats/overview` — vue d'ensemble : nombre de tâches, tâches en
  retard, dette de temps (avg/min/max), tâches complétées sur 30 jours,
  durée moyenne par tâche.
- `GET /stats/history` / `GET /stats/category-history` — historique
  bucketé jour/semaine/mois (QUE-46), global ou par tâche.
- `GET /stats/time-history` — courbe d'activité (temps passé), filtrable
  par `taskId`.
- `GET /stats/time-by-category` — temps passé par catégorie, filtrable par
  période (`total`/`week`/`month`) avec navigation précédent·e/suivant·e
  (`offset`, borné ≤ 0).

## Bonnes pratiques Git / PR

- **Un commit = un changement logique** (ex. modèle, puis routes, puis
  config) : pas de commit fourre-tout, chaque commit reste
  compilable/cohérent.
- Message de commit : ligne de résumé au présent décrivant le *pourquoi*,
  corps optionnel, référence ticket `QUE-xxx` si pertinent.
- Une PR par ticket ; description = résumé du changement + plan de test,
  pas une paraphrase du diff.

## Liens
- [[TaskManager]]
- [[Frontend]]
- [[Routes]]
- [[Modèle de données]]
- [[Récurrence]]
