#projet #taskmanager #angular #rust #mongodb

Application de gestion de tâches **récurrentes** (nom interne de l'app :
*TaskDays*), composée de deux dépôts séparés : [[Frontend]] (Angular/Ionic)
et [[Backend]] (Rust/Axum). Voir aussi [[Routes]] (toutes les routes front et
back), [[Modèle de données]] / [[Récurrence]] pour le moteur de récurrence, et
[[Séries]] pour les chaînes de tâches liées.

---

## But

Remplacer une liste de tâches classique par des tâches qui **reviennent**
selon un motif configurable (quotidien, hebdo, mensuel, annuel, ou « tous les
N jours/semaines/mois/ans »), avec suivi du temps passé, historique de
réalisation, et export vers un calendrier externe (Google Calendar, Apple
Calendrier, etc. via un flux ICS en lecture seule). Usage perso, déployé sur
Heroku.

## Fonctionnalités

- **Tâches récurrentes** — 5 motifs (`none`/`daily`/`weekly`/`monthly`/
  `yearly`/`custom`), saisonnalité (`activeMonths`), report (« repousser »)
  avec décalage jours/mois/années. Détail du moteur : [[Récurrence]].
- **Tâches libres** (QUE-164) — récurrence `free` : la tâche revient après
  chaque validation, mais **sans échéance programmée**. Sa date est une
  *programmation* facultative, pas une échéance : une tâche libre n'est donc
  jamais « en retard ». Socle des tâches enchaînées ([[Séries]]).
- **Séries de tâches liées** (QUE-165 → QUE-172) — enchaîner des tâches qui
  n'ont de sens que l'une après l'autre (lancer une machine → étendre →
  plier), avec délai par étape (de la minute à l'année), plusieurs
  *tours* d'une même chaîne en parallèle, et convergence de plusieurs
  chaînes sur une même tâche. Détail : [[Séries]].
- **Étapes informatives** (`steps`) — sous-liste cochable dans l'UI mais sans
  impact sur le statut de la tâche (purement indicatif).
- **Chrono** (QUE-120) — démarrage/pause/reprise du temps passé sur une
  tâche, **multitâche** (plusieurs chronos en pause simultanément, mais un
  seul en cours d'exécution à la fois — démarrer/reprendre l'un met les
  autres en pause), historique des sessions (`task-history-inprogress`).
- **Historique** — réalisations (`done`, avec durée/commentaire/« fait par
  quelqu'un d'autre »), reports (`postpone`), archivage (`archive`).
  Remise « à faire » possible (annule la dernière réalisation active plutôt
  que de la supprimer).
- **Catégories** — couleur, icône, mot-clé calendrier par défaut (hérité par
  les tâches qui n'en définissent pas).
- **Mot-clé Google Calendar** (« flair ») — associe une tâche/catégorie à un
  mot-clé reconnu par l'app Google Calendar (ex. *Coiffeur*, *Médecin*) pour
  afficher une petite icône dans l'agenda.
- **Flux calendrier ICS** (QUE-146) — abonnement en lecture seule
  (`/calendar/{token}.ics`), protégé par un jeton opaque dans l'URL (pas de
  header custom : les clients calendrier natifs n'en envoient pas),
  filtrable par tâche/catégorie, opt-in par tâche (`icsExport`).
- **Statistiques** — vue d'ensemble (retard, dette de temps, moyenne de
  durée), historiques bucketés jour/semaine/mois, temps passé par catégorie
  avec navigation semaine/mois précédent·e/suivant·e.
- **Vue calendrier** (front) — grille semaine/mois avec projection des
  occurrences à venir (approximation front, cf. [[Récurrence]]) + agenda
  détaillé du jour/semaine sélectionné·e.

## Stack technique (résumé)

| | Front — [[Frontend]] | Back — [[Backend]] |
|---|---|---|
| Dépôt | `TaskManager` | `TaskManager-backend` |
| Langage | TypeScript strict | Rust (édition 2024) |
| Framework | Angular 20 standalone + Ionic 8 + Capacitor 8 | Axum |
| État / persistance | NgRx Signals (`signalStore`, `withEntities`) | Driver officiel `mongodb` |
| Tests | Vitest (`@angular/build:unit-test`) | tests unitaires `#[cfg(test)]` (module `schedule`, modèles) |
| Déploiement | Heroku (`web: npm run serve:app`) | Heroku (`web: ./target/release/webserver`) |

Détails complets : [[Frontend]] (architecture page/smart/dumb, stores, flux
de synchronisation) et [[Backend]] (couches model/db/routes, groupes
d'authentification).

## Base de données

**MongoDB Atlas**, une seule base applicative. Collections principales :
`tasks`, `category`, `task-history-done`, `task-history-postpone`,
`task-history-archive`, `task-history-inprogress`, `task-series` /
`task-series-instances` ([[Séries]]), plus les collections utilisateur/auth.
Voir [[Modèle de données]] pour le détail des champs.

## Authentification

Double vérification sur les routes protégées (cf. [[Routes]] pour le détail
des trois groupes) :
1. **`X-Token`** — token applicatif HMAC (obtenu via `POST /token`),
   vérifié par `verify_token_middleware`.
2. **JWT** (`Authorization: Bearer`) — obtenu via `POST /auth`, vérifié par
   `verify_jwt_middleware` (`axum_jwt`).

Le flux calendrier ICS (`GET /calendar/{token}.ics`) est **volontairement
public** (aucun des deux middlewares) : protégé uniquement par un jeton
opaque dans l'URL, résolu en utilisateur côté handler — les clients
calendrier natifs (iOS/Android/Google Calendar) ne savent pas envoyer de
headers custom.

## Liens
- [[Frontend]]
- [[Backend]]
- [[Routes]]
- [[Modèle de données]]
- [[Récurrence]]
- [[Séries]]
