## quizup-workspace

Workspace local pour cloner et piloter les repositories de l'organisation QuizUp.

### Scripts de productivite git multi-repos

Le workspace fournit cinq scripts pour eviter la repetition des commandes git quand tu travailles sur une meme feature dans plusieurs repos.

#### 1) `start-dev`

Objectif: creer et checkout une branche sur les repos cibles avec la convention:

`type/scope/nom-de-feature`

Regles:
- `type` doit etre `feature`, `fix` ou `chore`
- base de branche: **toujours** `origin/main`
- flow par repo: `fetch` -> `checkout main` -> `pull --ff-only origin main` -> `checkout -b <branch> origin/main`
- echec si la branche existe deja en local ou sur origin
- echec si le repo contient des changements locaux
- enregistre une session locale dans `.dev-session.env` (fichier ignore par git)
- les saisies interactives sont nettoyees (sequences ANSI/fleches et caracteres de controle) pour eviter les suffixes parasites

Mode interactif:

```bash
make start-dev
```

Mode non interactif:

```bash
make start-dev TYPE=feature SCOPE=profiles FEATURE=spring-profiles DESC="rollout spring profiles" REPOS=quizup-identity,quizup-theme
```

Mode dry-run:

```bash
make start-dev TYPE=feature SCOPE=profiles FEATURE=spring-profiles ALL=true DRY_RUN=true
```

#### 2) `continue-dev`

Objectif: relire la session locale `.dev-session.env` et remettre les repos cibles sur la branche active du dev en cours.

Regles:
- lit `branch` et `repos` depuis `.dev-session.env` par defaut
- flow par repo: `fetch` -> `checkout <branch-session>` -> `pull --ff-only origin <branch-session>`
- echec si le repo contient des changements locaux
- echec si la branche de session n'existe ni en local ni sur origin
- si la branche n'existe qu'en local, checkout local + warning (pas de pull distant)

Execution depuis la session:

```bash
make continue-dev
```

Execution ciblee:

```bash
make continue-dev REPOS=quizup-identity,quizup-theme
```

Mode dry-run:

```bash
make continue-dev DRY_RUN=true
```

#### 3) `apply-dev`

Objectif: ajouter, commit et push les changements courants sur les repos cibles.

Regles:
- commit automatique par repo avec convention fixe:
  - `type(<repo>): <description>`
  - exemple: `feature(quizup-identity): add spring profile deployment support`
- `git add -A` est applique avant commit
- push sur la branche courante du repo
- echec si le repo est sur `main`
- par defaut, lit `type`, `description`, `repos` et `branch` depuis `.dev-session.env`
- echec si la branche courante d'un repo ne correspond pas a la branche de la session active

Mode interactif:

```bash
make apply-dev
```

Le mode interactif s'appuie d'abord sur la session locale si elle existe.

Mode non interactif:

```bash
make apply-dev TYPE=feature DESC="add spring profile rollout" REPOS=quizup-identity,quizup-theme
```

Mode dry-run:

```bash
make apply-dev TYPE=feature DESC="add spring profile rollout" ALL=true DRY_RUN=true
```

#### 4) `exit-dev`

Objectif: remettre les repos sur `main` et revenir dans un etat production-ready.

Regles:
- flow par repo: `fetch` -> `checkout main` -> `pull --ff-only origin main`
- echec si le repo contient des changements locaux
- supprime `.dev-session.env` si tout se termine avec succes

Execution complete (par defaut):

```bash
make exit-dev
```

Execution ciblee:

```bash
make exit-dev REPOS=quizup-identity,quizup-theme
```

Mode dry-run:

```bash
make exit-dev ALL=true DRY_RUN=true
```

#### 5) `status-dev`

Objectif: afficher la session dev active et l'etat git des repos (branche + clean/dirty).

Execution complete (par defaut):

```bash
make status-dev
```

Execution ciblee:

```bash
make status-dev REPOS=quizup-identity,quizup-theme
```

### Notes

- Les repos cibles sont lus depuis `workspace.yml`.
- Le mapping des dossiers suit `scripts/boostrap.sh`:
  - `library -> libraries/`
  - `devops -> devops/`
  - `web-application -> web-applications/`
  - `service -> services/`
- Le fichier de session locale est `.dev-session.env`.
