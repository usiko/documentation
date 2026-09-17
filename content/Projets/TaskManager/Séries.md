#taskmanager #séries

Séries de tâches liées du projet [[TaskManager]] (QUE-165 → QUE-172) :
enchaîner des tâches qui n'ont de sens que **l'une après l'autre**, là où la
[[Récurrence]] ne sait exprimer qu'un motif calendaire. Modèle des
collections dans [[Modèle de données]], routes dans [[Routes]].

> [!info] État
> Développée sur la branche d'intégration `feature/serie` des deux dépôts
> (front et back), pas encore fusionnée dans `master` au moment de cette
> page.

---

## Le besoin

« Lancer une machine » → « étendre le linge » → « plier le linge ». La
deuxième tâche n'est pas due tous les mardis : elle est due *quand la
première a été faite*, et 40 minutes plus tard. Une récurrence, même
`custom`, ne sait pas exprimer ça — elle ne connaît qu'une grille ou un
intervalle depuis la dernière réalisation de la tâche elle-même.

## Deux objets distincts

C'est la distinction structurante de la feature.

| | Configuration — `task-series` | Tour — `task-series-instances` |
|---|---|---|
| Répond à | *comment* la chaîne s'enchaîne | *un parcours en cours* de cette chaîne |
| Durée de vie | permanente (éditée par l'utilisateur) | de la validation de la tête à celle de la dernière étape |
| Contenu | `headTaskId`, `steps[]` ordonnées, `name?` | `seriesId`, `currentStepId`, `currentTaskId`, `dueDate`, `startedAt` |

Une configuration peut donc être **en cours plusieurs fois en parallèle** :
deux machines lancées coup sur coup donnent deux tours, chacun avec sa
propre échéance d'étendage. La collection des tours ne contient que ce qui
est **en attente** — un tour terminé disparaît.

> [!tip] Pourquoi pas un simple champ sur la tâche
> Parce que la `dueDate` d'une tâche n'en porte qu'une. Deux machines à
> étendre, ou deux chaînes différentes qui convergent sur « étendre le
> linge » (la lessive *et* le sport), se marcheraient dessus. Chaque tour
> porte sa propre échéance ; celle de la tâche en est **dérivée**.

## Convergence

Une même tâche peut être :
- une **étape de plusieurs chaînes** (deux lessives qui mènent au même
  étendage) ;
- la **tête de l'une et une étape d'une autre**.

`db::task_series::advance_after_validation` récupère donc **toutes** les
séries qui référencent la tâche validée (`headTaskId` **ou** `steps.taskId`)
et fait avancer chacune indépendamment, sur son propre chemin.

## Ce que solde une validation

Toutes les chaînes en attente sur la tâche ne sont pas forcément soldées
d'un coup — plier le linge d'une machine ne plie pas celui de la suivante.
`instances_cleared_by_validation` tranche :

| Cas | Tours soldés |
|---|---|
| Étape **facultative** (`optional`) | **tous** les tours qui attendaient cette étape (une séance de pliage solde plusieurs machines) |
| Étape **obligatoire** | seulement le tour **le plus urgent** |
| Sélection explicite (QUE-170) | exactement les tours cochés, via `UpdateTask.seriesInstanceIds` |

La sélection explicite existe parce que la règle par défaut se trompe
forcément parfois : « j'ai plié deux lessives, mais il m'en reste une pas
sèche ». Le front propose donc de confirmer chaîne par chaîne quand une
validation en solderait plusieurs ; sans sélection, le comportement
historique s'applique.

### Valider « pour la tâche seule »

`UpdateTask.advanceSeries: false` valide la tâche (historique, résumé) sans
solder ni lancer de tour — c'est ce qu'envoie l'onglet « Libre » : étendre
le linge *parce qu'il traînait* ne consomme pas l'étendage attendu par une
machine en cours.

L'entrée d'historique garde la trace de l'arbitrage : `TaskHistoryDone`
porte les `seriesIds` auxquels la validation a participé, ce qui distingue
après coup une réalisation faite dans une chaîne d'une réalisation faite
pour la tâche seule.

## Échéance dérivée

L'échéance d'une tâche attendue par des tours est celle du **tour le plus
ancien qui l'attend** (`sync_due_date`), pour toutes les étapes — le retard
s'accumule au lieu d'être repoussé à chaque cycle. Corollaire à connaître :

> [!warning] Annuler un tour doit relâcher l'échéance
> `sync_due_date` n'écrit rien quand plus aucun tour n'attend la tâche —
> l'échéance du tour annulé serait donc restée orpheline. D'où
> `release_due_date`, appelée à la fermeture d'un tour (QUE-166).

## Délais entre étapes

Chaque étape porte un délai optionnel appliqué depuis la validation de la
précédente ; absent, la tâche est programmée **dès validation**.

```ts
interface ITaskSeriesDelay {
  value: number;
  unit: 'minute' | 'hour' | 'day' | 'week' | 'month' | 'year';
}
```

Type d'unité **propre à la série** (`TaskSeriesDelayUnit`), distinct du
`RecurrenceUnit` de la [[Récurrence]] : un enchaînement se règle souvent à
l'heure ou à la minute (QUE-172), là où une récurrence de tâche ne descend
pas sous la journée. `delay_to_offset` convertit le délai en `TaskOffset` —
les unités infra-journalières passent par son champ `minutes`, déjà appliqué
tel quel par `schedule::shift_offset` (pas de calendrier, donc pas de saut
DST à cette échelle).

## Annuler ou terminer un tour (QUE-166)

Depuis la liste des tâches, la pastille numérotée d'une occurrence ouvre les
actions du tour :
- **Annuler** — `DELETE /task-series-instances/{id}` : le tour se referme,
  l'échéance qu'il portait est relâchée.
- **Terminer** — `POST /task-series-instances/{id}/complete` : valide l'étape
  attendue **et toutes les suivantes** (`remaining_task_ids`), plutôt que
  d'abandonner le tour en silence.

## Côté front

| Où | Ce qu'on y voit |
|---|---|
| Onglet « Série » d'une tâche (`/task/details/:id/:tab`) | Chronologie de la chaîne : tête, étapes, délais, position courante. Temps estimé total et moyen de la chaîne (QUE-167) |
| Liste des tâches, onglet « À faire » | Une ligne **par tour** quand plusieurs attendent la même tâche, chacune avec son échéance et son numéro `#N` ; pastille de série discrète (grise) sur une tâche membre d'une chaîne qu'aucun tour n'attend |
| Page « Mes séries » (`/series/list`) | Toutes les chaînes, celles en cours d'abord, dépliables sur leurs étapes |
| Bloc série du chrono | La chaîne en cours, son nom, les numéros des tours arrêtés là, le délai avant chaque étape (QUE-171) |

Les numéros `#N` sont un **ordre de lancement global** (toutes chaînes
confondues, par `startedAt` croissant, cf. `TaskSeriesInstanceStore.runOrdinals`) :
ils servent à reconnaître *de quel lancement* vient une occurrence, pas à
compter les tours d'une chaîne donnée.

Stores et synchronizers dédiés — `NGRX/task-series/`,
`NGRX/task-series-instance/`, `synchronizer/task-series{,-instance}.synchronizer.ts` —
selon le flux décrit dans [[Frontend]]#Flux de données (CQRS-léger via subjects).

## Tickets

| Ticket | Apport |
|---|---|
| QUE-164 | Récurrence `free` (« tâche libre »), socle des tâches d'une chaîne — cf. [[Récurrence]] |
| QUE-165 | Chaînes de tâches : configuration, tours, avancement à la validation, onglet « Série » |
| QUE-166 | Annuler / terminer un tour depuis la liste |
| QUE-167 | Temps estimé total et moyen d'une chaîne |
| QUE-168 | Une occurrence par tour dans la liste, numérotée |
| QUE-169 | Nom optionnel d'une série + page « Mes séries » |
| QUE-170 | Choisir les chaînes qu'une validation solde |
| QUE-171 | Bloc série du chrono : nom, numéros, délais, chaînes convergentes |
| QUE-172 | Délais à l'heure et à la minute ; pastille effacée hors occurrence en cours |

## Liens
- [[TaskManager]]
- [[Frontend]]
- [[Backend]]
- [[Routes]]
- [[Modèle de données]]
- [[Récurrence]]
