#taskmanager #récurrence

Moteur de récurrence du projet [[TaskManager]] : calcul de la prochaine
échéance (`nextDueDate`) d'une tâche. Logique **back** (source de vérité,
`src/utils/schedule.rs` de [[Backend]]) + duplication **approximative**
côté [[Frontend]] pour l'affichage calendrier. Voir [[Modèle de données]]
pour la forme de `TaskRecurrence`.

---

## Deux familles de motifs

`compute_next_due_date(task, last_done)` (`schedule.rs`) — `last_done` =
date de la dernière réalisation **active**, `None` si jamais réalisée :

### Motifs calendaires — `daily` / `weekly` / `monthly` / `yearly`

**Grille fixe** : la prochaine échéance est la première occurrence du motif
strictement postérieure à `last_done` (ou dès l'ancre — `dueDate`/
`createdAt` —, borne incluse, si jamais réalisée). Une réalisation en retard
**ne décale pas la grille** : le motif rattrape simplement la prochaine
occurrence non consommée (ex. « tous les lundis » reste calé sur les lundis,
quel que soit le jour réel de validation).

- `daily` : `hours[]` (défaut minuit) donne la grille de créneaux du jour,
  interprétée en **heure de Paris** (DST géré), pas en UTC. Une validation
  couvre le **jour civil parisien entier** — la prochaine échéance est le
  premier créneau du jour suivant, même si tous les créneaux du jour n'ont
  pas été atteints.
- `weekly` / `monthly` / `yearly` : granularité **jour** (pas d'heure).
  Si `weekDays`/`monthDays`/`months` est vide, le motif suit le jour de la
  semaine/mois/mois de l'année de l'**ancre** (`dueDate`/`createdAt`).

### Motif flottant — `custom` (« tous les N jours/semaines/mois/ans »)

L'intervalle se compte depuis la **dernière réalisation réelle** (ou
l'ancre si jamais réalisée), pas depuis une grille fixe :
`next = last_done + interval × unit` (`step_custom`). Une réalisation très
en retard ne « rattrape » rien : la prochaine échéance suit simplement la
date réelle de validation, décalée de l'intervalle.

> [!info] Choix UI : « toutes les N semaines » = `custom` + `unit: week`
> Le sélecteur de récurrence (`TaskRecurrenceComponent`) n'expose
> l'intervalle (`interval`/`unit`) **que** pour le type `custom` — `weekly`
> n'a qu'une liste de jours de semaine, sans notion d'intervalle. Une tâche
> « toutes les 2/3 semaines » est donc toujours modélisée en `custom` +
> `unit: 'week'`, jamais en `weekly`.

## Saisonnalité (`activeMonths`)

Appliquée après le motif : si le mois de l'occurrence trouvée n'est pas
actif, le moteur avance (jour par jour pour `daily`/calendaires, par
intervalle complet pour `custom`) jusqu'au prochain mois actif.

## Report (offset)

`Task.offset` (`{ days, months, years }`) est le décalage **cumulé** des
reports (« repousser la tâche ») — additionné (pas écrasé) à chaque nouveau
report, pour que les reports successifs se cumulent (QUE-90). Il avance la
**borne de recherche** de la prochaine occurrence
(`shift_offset(natural_start, offset)`) avant que le moteur cherche
l'occurrence : la prochaine échéance ne peut jamais tomber avant
`repère + offset`.

> [!warning] QUE-91 — offset annulé s'il est un multiple de la période
> Avant QUE-91, l'implémentation décalait le repère **en arrière** puis
> re-décalait le résultat trouvé du même montant — une opération qui
> s'annule exactement dès que l'offset est un multiple de la période du
> motif (ex. reporter une tâche hebdomadaire de 2 semaines rendait le
> report invisible). Fixé en décalant la **borne de recherche vers l'avant**
> une seule fois, sans compensation a posteriori.

### Bug corrigé — l'offset restait actif indéfiniment

**Symptôme rapporté** : une tâche récurrente revient systématiquement plus
tard que prévu (ex. « toutes les 2 semaines » revenant ~10 jours après
l'intervalle attendu), et pour un motif `custom` en semaines, une dérive du
**jour de la semaine** au fil des cycles alors que rien n'avait été
reporté récemment.

**Cause racine** : `task.offset` n'était **jamais remis à zéro**. Comme
`compute_next_due_date` l'applique à **chaque** calcul (pas seulement à
l'occurrence immédiatement suivant le report), un report ponctuel
continuait à décaler **toutes** les occurrences futures, indéfiniment — pour
`custom`, l'offset s'additionne directement au résultat (pas de grille pour
l'« absorber »), donc chaque cycle suivant héritait du même décalage
supplémentaire, y compris le jour de la semaine si le report n'était pas un
multiple de 7 jours.

**Fix** ([`TaskManager-backend#48`](https://github.com/usiko/TaskManager-backend/pull/48)) :
`db::task::update` remet `offset` à `TaskOffset::default()` dès que la tâche
passe à `done` (sauf si la même requête porte elle-même un nouveau report) —
la validation de l'occurrence reportée **consomme** le report ; les cycles
suivants repartent de zéro.

> [!warning] À vérifier en review
> Toute nouvelle voie qui modifie `Task.offset` (ou qui ajoute une
> transition de statut supplémentaire vers `done`) doit préserver ce reset —
> sans lui, l'offset redevient perpétuel.

## Projection d'occurrences (`project_occurrences`)

Utilisée par le flux ICS ([[Backend]]#Flux calendrier ICS) : boucle sur
`compute_next_due_date` (chaque occurrence trouvée devient le `last_done`
de l'itération suivante) jusqu'à une fenêtre glissante (`window_end`,
60 jours) ou un plafond anti-boucle infinie (`max_count`, 120). Réutilise
le moteur exact plutôt que de dupliquer la logique en `RRULE` ICS — un
mapping RRULE serait fragile pour `custom` (flottant, pas une grille fixe).

## Duplication front (approximation, affichage seulement)

`TasksStore.calendarOccurrences` (`occurrenceDatesInRange`,
`task.store.ts`) reproduit les mêmes règles **côté front**, pour peupler la
grille calendrier sans aller-retour réseau à chaque navigation
semaine/mois. Ancrée sur `nextDueDate` (calculée par le back) puis
extrapolée localement avec l'intervalle **courant** de la récurrence — la
seule échéance qui fasse foi reste `nextDueDate`, recalculée par le back à
chaque validation. Documenté comme approximation dans le code : ne
supporte pas nativement les changements de motif à mi-fenêtre (cohérent
avec le fait qu'une récurrence `custom` n'a de toute façon pas
d'occurrences futures « garanties » au-delà de la prochaine, cf. ci-dessus).

### Bug corrigé — PUT successifs sur une même tâche

**Symptôme rapporté** : changer l'intervalle de récurrence plusieurs fois
de suite (ex. 3 → 2 → 1 → 2 semaines) faisait parfois « rester coincée » la
tâche sur une valeur intermédiaire dans le calendrier (toutes les semaines
au lieu de toutes les 2 semaines), jusqu'à un rechargement complet de la
page.

**Cause racine** : `TasksSynchronizer` envoyait les PUT de mise à jour
générique (`onUpdate$`) via un `mergeMap` global — plusieurs PUT sur la
même tâche partaient en parallèle, sans garantie d'ordre sur les réponses
réseau. La réponse d'un PUT plus ancien (ex. intervalle = 1) pouvait
arriver **après** celle d'un PUT plus récent (intervalle = 2) et écraser
(`setItem`) le store avec les champs obsolètes.

**Fix** ([`TaskManager#109`](https://github.com/usiko/TaskManager/pull/109)) :
`groupBy(id)` + `concatMap` sérialise les PUT d'une même tâche (chacun
attend la réponse du précédent avant de partir), en laissant des tâches
différentes se traiter en parallèle entre elles. Voir [[Frontend]]#Flux de
données (CQRS-léger via subjects).

## Tests de référence

`src/utils/schedule.rs` (module `#[cfg(test)] mod tests`, [[Backend]]) —
couvre notamment : heure de Paris vs UTC pour `daily`, validation couvrant
la journée civile entière, motif `custom` flottant sur réalisation en
retard, non-avancement tant que le cycle courant n'est pas validé,
saisonnalité, et les deux cas QUE-91 (report multiple de la période, motifs
calendaire et `custom`).

## Liens
- [[TaskManager]]
- [[Frontend]]
- [[Backend]]
- [[Modèle de données]]
- [[Routes]]
