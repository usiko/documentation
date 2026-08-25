#projet #commonangular #angular #librairie

Workspace Angular CLI destiné à héberger une **librairie partagée** (`common`)
de composants/services réutilisables entre les différents projets front
Angular d'usiko (ex. [[mongoManager]]). Dépôt : `usiko/common-angular`.

---

## But

Éviter de dupliquer du code (composants, services, utilitaires) entre les
projets Angular perso en le centralisant dans une librairie publiable, plutôt
que de copier-coller entre dépôts. Généré via `ng generate library`.

## État actuel

Projet au stade **squelette** — deux commits seulement (`initial commit`,
`add library`), aucune fonctionnalité métier encore développée :

- Le workspace racine (`common-angular`) ne contient qu'un seul projet
  Angular : la librairie `common` (`projects/common`).
- La librairie expose pour l'instant un unique composant placeholder généré
  par le CLI (`lib-common`, template `<p>common works!</p>`), à remplacer par
  le premier composant/service réellement partagé.
- `public-api.ts` ne réexporte que ce composant placeholder.

À mettre à jour au fur et à mesure que du contenu réel est ajouté à la
librairie.

## Stack technique

- **Angular 21** (workspace CLI, `projectType: library`), builder
  `@angular/build:ng-packagr` pour la compilation de la librairie.
- **TypeScript strict** (`strict`, `noImplicitOverride`,
  `noPropertyAccessFromIndexSignature`, `noImplicitReturns`,
  `noFallthroughCasesInSwitch`, cible `ES2022`).
- **Vitest** comme test runner (`@angular/build:unit-test`), remplace Karma
  par défaut du CLI classique — cf. `projects/common/README.md`, qui lui,
  généré automatiquement, mentionne encore Karma par erreur.
- **Prettier** (`printWidth: 100`, guillemets simples, parser `angular` pour
  les templates HTML).
- `ng-package.json` : point d'entrée `src/public-api.ts`, sortie compilée
  dans `dist/common` (à la racine du workspace, hors de `projects/`).

## Structure

```
common-angular/
├── angular.json              # config du workspace, un seul projet : "common"
├── tsconfig.json             # config TS racine, path mapping "common" -> ./dist/common
└── projects/
    └── common/
        ├── ng-package.json   # config ng-packagr (entryFile, dest)
        ├── package.json      # métadonnées npm de la librairie publiée
        ├── src/
        │   ├── public-api.ts # surface publique exportée par la librairie
        │   └── lib/
        │       ├── common.ts       # composant placeholder "lib-common"
        │       └── common.spec.ts  # test associé
        └── tsconfig.lib*.json / tsconfig.spec.json
```

Le `tsconfig.json` racine mappe l'import `"common"` vers `./dist/common` :
un projet consommateur peut donc importer la librairie compilée via
`import { ... } from 'common'` une fois le build effectué (ou via un lien
npm local le temps qu'elle ne soit pas publiée sur un registre).

## Commandes utiles

```bash
# Build de la librairie (production par défaut)
ng build common

# Build en mode watch (développement)
ng build common --configuration development --watch

# Tests unitaires (Vitest)
ng test

# Générer un nouveau composant/service dans la librairie
ng generate component nom --project=common
```

Le build compile `projects/common` et place le résultat publiable dans
`dist/common` (voir `ng-package.json`). Publication npm ensuite via
`cd dist/common && npm publish` (registre non défini pour l'instant — projet
pas encore publié).

## Points d'attention

- Pas de serveur de développement au sens applicatif (`ng serve`) : c'est une
  librairie, pas une application — le `README.md` racine généré par défaut
  par le CLI mentionne `ng serve`/`http://localhost:4200`, ce qui ne
  s'applique pas ici (pas d'application shell dans ce workspace pour l'instant).
- `.clinerules` présent à la racine configure un outil tiers (`rtk`, proxy
  CLI pour l'assistant Cline) — spécifique à cet outil, sans rapport avec le
  build/déploiement du projet.

## Liens
- [[mongoManager]] — projet front consommateur potentiel de cette librairie
