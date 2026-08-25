#taskmanager #mongodb

Modèle de données du projet [[TaskManager]] — collections MongoDB et formes
DTO échangées entre [[Backend]] et [[Frontend]]. Le détail du calcul de
`nextDueDate` (récurrence) est dans [[Récurrence]].

---

## `Task` (collection `tasks`)

Champs principaux (`src/model/task_model.rs`, camelCase côté JSON) :

| Champ | Type | Notes |
|---|---|---|
| `id` | `string` | `_id` Mongo, généré côté front (UUID) ou serveur |
| `userId` | `string` | Propriétaire (`sub` du JWT) — jamais renvoyé au front dans le DTO, mais sérialisé côté DB (cf. [[Backend]]#Convention modèle DB vs DTO HTTP) |
| `title` | `string` | Alias JSON accepté : `name` |
| `description` | `string?` | |
| `steps` | `TaskStep[]` | Étapes informatives (`id`, `text`), aucun impact sur le statut |
| `calendarKeyword` | `CalendarKeyword?` | Mot-clé Google Calendar, prime sur celui de la catégorie |
| `dueDate` | `DateTime?` | Utilisée si `recurrence.type === 'none'`, ou comme ancre initiale d'une récurrente (repli sur `createdAt` si absente — le front envoie `null` pour une tâche créée récurrente) |
| `duration` | `{ min, max }` | Fourchette estimée, **en millisecondes** (QUE-120) |
| `recurrence` | `TaskRecurrence` | Voir [[Récurrence]] |
| `status` | `todo \| in-progress \| done \| cancelled` | Ne redescend jamais seul à `todo` pour une récurrente — le statut affiché dérive de `nextDueDate`/`doneSummary`, jamais de ce champ seul |
| `disabled` | `bool?` | Tâche inactive mais conservée (ne génère plus d'occurrences) |
| `archived` / `archivedAt` | `bool` / `DateTime?` | Auto-archivage à la validation pour une tâche **ponctuelle** uniquement ; jamais pour une récurrente |
| `activeMonths` | `u8[]?` | Saisonnalité (0=Jan…11=Déc) ; vide/absent = active toute l'année |
| `categoryId` | `string?` | |
| `icsExport` | `bool` | Opt-in export ICS (QUE-152), `false` par défaut |
| `offset` | `{ days, months, years }` | Décalage **cumulé** des reports (QUE-90/91) — jamais renvoyé au front (`skip_serializing`), utilisé uniquement par `compute_next_due_date`. Voir [[Récurrence]]#Report (offset) pour son cycle de vie |
| `createdAt` / `updatedAt` | `DateTime` | |

### Champs calculés (jamais stockés, renvoyés dans `TaskResponse`)

| Champ | Calculé par | Description |
|---|---|---|
| `nextDueDate` | `utils::schedule::compute_next_due_date` | Prochaine échéance — voir [[Récurrence]] |
| `doneSummary` | `TaskDoneSummary::from_done` | Dernière réalisation active (date, commentaire, durée, moyenne) ; masqué si `nextDueDate` est déjà due |
| `timeSpent` | `TaskTimeSpent::compute` | Temps total estimé passé (somme des durées réelles + moyenne pour les réalisations sans durée), avec marge d'erreur |
| `activeChrono` | dérivé de `task-history-inprogress` | Session de chrono en cours (QUE-120), `null` sinon |

## `TaskRecurrence`

```ts
interface ITaskRecurrence {
  type: 'none' | 'daily' | 'weekly' | 'monthly' | 'yearly' | 'custom';
  hours: number[];     // daily   : heures (0-23)
  weekDays: number[];  // weekly  : 0=Lun … 6=Dim
  monthDays: number[]; // monthly : 1-31
  months: number[];    // yearly  : 0=Jan … 11=Déc
  interval: number;    // custom uniquement (défaut 1)
  unit: 'day' | 'week' | 'month' | 'year'; // custom uniquement
}
```

`daily`/`weekly`/`monthly`/`yearly` sont des motifs **calendaires** (grille
fixe) ; `custom` (« tous les N jours/semaines/mois/ans ») est un motif
**flottant** (calé sur la dernière réalisation réelle). Détail complet des
règles de calcul : [[Récurrence]].

## `Category` (collection `category`)

| Champ | Type | Notes |
|---|---|---|
| `id` / `userId` | `string` | Même remarque que `Task.userId` sur la sérialisation |
| `name` | `string` | |
| `color` | `string` | |
| `icon` | `string?` | |
| `calendarKeyword` | `CalendarKeyword?` | Repli utilisé par une tâche de la catégorie qui n'a pas son propre mot-clé |

## Historique (`task-history-*`)

Quatre collections, jamais purgées automatiquement (une réalisation
annulée est marquée `cancelled: true`, pas supprimée) :

| Collection | Modèle | Notes |
|---|---|---|
| `task-history-done` | `TaskHistoryDone` | `date`, `comment?`, `duration?` (ms), `doneByMe?`, `cancelled`, `cancelledAt?`. Une remise « à faire » annule la dernière entrée **active** plutôt que de la supprimer (QUE-105) |
| `task-history-postpone` | `TaskHistoryPostpone` | `offset` appliqué, nouvelle `dueDate` résultante — purement informatif côté front, le calcul/la persistance sont faits côté back |
| `task-history-archive` | `TaskHistoryArchive` | Transitions archivé ↔ désarchivé |
| `task-history-inprogress` | `TaskHistoryInProgress` | Sessions de chrono (QUE-120) : `startedAt`, `activity: {start, stop}[]`, `completed`, `cancelled`, `checkedSteps` |

## `CalendarKeyword`

Enum de mots-clés reconnus par l'app Google Calendar (icône dans l'agenda),
sous-ensemble volontairement restreint (catégories pertinentes pour une app
de tâches perso/domestique : *Coiffeur*, *Médecin*, *Plombier*, *Réparation*,
*Restaurant*…). Réglable par tâche **et/ou** par catégorie — la tâche prime
si les deux sont renseignés (`calendar_feed::effective_keyword`).

## Liens
- [[TaskManager]]
- [[Frontend]]
- [[Backend]]
- [[Routes]]
- [[Récurrence]]
