# CI/CD Java Microservices — Best Practices GitHub

## Conventional Commits

Le format Conventional Commits structure les messages de commit pour les rendre exploitables automatiquement par les
outils de release.

```
<type>(<scope>): <description>

[body optionnel]
[BREAKING CHANGE: <description>]
```

### Types et impact sur le versioning

| Type                        | Usage                              | Impact SemVer   |
|-----------------------------|------------------------------------|-----------------|
| `feat`                      | Nouvelle fonctionnalité            | MINOR → `1.1.0` |
| `fix`                       | Correction de bug                  | PATCH → `1.0.1` |
| `feat!` / `BREAKING CHANGE` | Rupture de compatibilité           | MAJOR → `2.0.0` |
| `chore`                     | Tâches techniques (build, deps)    | Aucun           |
| `docs`                      | Documentation                      | Aucun           |
| `test`                      | Ajout/correction de tests          | Aucun           |
| `refactor`                  | Refactoring sans ajout fonctionnel | Aucun           |
| `perf`                      | Amélioration de performance        | PATCH           |

### Règles de rédaction

- Utiliser l'impératif présent : `add` plutôt que `added`
- Limiter la ligne de titre à **72 caractères max**
- Ajouter un `scope` pour identifier le microservice concerné : `feat(quiz-service): add leaderboard endpoint`
- Utiliser le corps du commit pour expliquer le *pourquoi* des changements complexes

***

## Semantic Versioning — `MAJOR.MINOR.PATCH`

- **MAJOR** : changement incompatible avec l'API existante (breaking change)
- **MINOR** : nouvelle fonctionnalité rétrocompatible
- **PATCH** : correction de bug rétrocompatible

En phase de développement initial, utiliser `0.x.y` pour signaler que l'API n'est pas encore stable. Les versions
`-SNAPSHOT` côté Maven indiquent un artefact en cours de développement.

***

## Stratégie de branches — GitHub Flow

Pour des microservices en déploiement continu, **GitHub Flow** est recommandé plutôt que GitFlow : plus léger et adapté
aux livraisons fréquentes.

```
main (production-ready, protégée)
  └── feature/quiz-service/add-leaderboard
  └── fix/lobby-service/timeout-crash
  └── chore/deps/upgrade-spring-boot-3.4
```

### Nommage des branches (`type/scope/description`)

- `feature/user-service/add-oauth-pkce`
- `fix/gateway/cors-preflight-error`
- `release/v1.3.0` (si release planifiée)
- `hotfix/v1.2.1` (correctif urgent en prod)

### Cycle de vie d'une branche

1. Créer une branche depuis `main` : `git checkout -b feat/quiz-service/scoring`
2. Commiter avec Conventional Commits
3. Ouvrir une Pull Request dès le début (draft PR conseillé)
4. CI passe (build + tests)
5. Code review obligatoire (au moins 1 approbateur)
6. Merge dans `main` via squash ou merge commit
7. Supprimer la branche après merge

***

## Tags & Releases — Automatisation avec `semantic-release`

L'outil **`semantic-release`** analyse les commits depuis le dernier tag, détermine la prochaine version SemVer, crée le
tag Git, met à jour le CHANGELOG et publie la release — sans intervention manuelle.

### Configuration `.releaserc.yml`

```yaml
branches:
  - main
  - name: develop
    prerelease: true  # génère 1.2.0-develop.1
plugins:
  - [ "@semantic-release/commit-analyzer", { preset: "conventionalcommits" } ]
  - [ "@semantic-release/release-notes-generator", { preset: "conventionalcommits" } ]
  - "@semantic-release/changelog"
  - "@semantic-release/github"
```

### Alternative Maven — Maven Release Plugin

Pour ceux qui préfèrent rester dans l'écosystème Maven natif, le Maven Release Plugin gère le cycle SNAPSHOT → release :

1. Change `1.2.0-SNAPSHOT` → `1.2.0` dans le POM
2. Commit + Tag `v1.2.0`
3. Bump vers `1.3.0-SNAPSHOT`
4. Commit

***

## Pipeline GitHub Actions

### Workflow CI (sur chaque PR)

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
    branches: [ main, develop ]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'

      - name: Lint commit messages
        uses: wagoid/commitlint-github-action@v6

      - name: Build & Test
        run: mvn -B verify
```

### Workflow Release (sur push dans `main`)

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    branches: [ main ]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # indispensable pour semantic-release
          persist-credentials: false

      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'

      - name: Semantic Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          npm install -g semantic-release \
            @semantic-release/changelog \
            @semantic-release/git \
            conventional-changelog-conventionalcommits
          npx semantic-release
```

> ⚠️ `fetch-depth: 0` est **obligatoire** — sans lui, `semantic-release` ne peut pas lire l'historique des commits pour
> calculer la prochaine version.

***

## Protection des branches — Règles GitHub

À configurer sur `main` dans **Settings > Branches** :

- ✅ **Require pull request reviews** — au moins 1 approbation
- ✅ **Require status checks to pass** — build + tests CI obligatoires
- ✅ **Dismiss stale reviews** — invalide les approbations après nouveau commit
- ✅ **Require branches to be up to date** — force le rebase avant merge
- ✅ **Restrict who can push** — uniquement via PR

***

## Flux global

```
dev: feat(quiz-service): add scoring api
         │
         ▼
    feature/branch
         │  PR + CI (build, tests, lint commits)
         ▼
        main  ──────────────────────────────▶  semantic-release
                                                      │
                                            analyse commits since last tag
                                                      │
                                            bump version (SemVer)
                                                      │
                                            git tag v1.3.0
                                                      │
                                            update CHANGELOG.md
                                                      │
                                            GitHub Release + artefacts
```