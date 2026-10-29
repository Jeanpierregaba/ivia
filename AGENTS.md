# AGENTS.md — Instructions pour l'agent

<!--
Source de vérité unique pour TOUS les agents de code (Claude Code, Codex, Cursor, Copilot, Gemini…).
CLAUDE.md se contente d'importer ce fichier.

Ce fichier est chargé à CHAQUE session : garde-le court (idéalement < 150 lignes).
Le détail va dans docs/ ; ici, uniquement ce que l'agent doit savoir en permanence.
Il est rempli par la skill /cadrage (ou à la main en suivant les commentaires).
-->

## Statut du cadrage

**NON FAIT**

<!-- /cadrage remplace "NON FAIT" par "FAIT (AAAA-MM-JJ)" une fois les docs remplies. -->

> Tant que le statut est « NON FAIT » : si l'utilisateur demande de coder une fonctionnalité,
> propose-lui d'abord de lancer `/cadrage` (ou de suivre `.claude/skills/cadrage/SKILL.md`).
> Un prototype jetable explicitement demandé reste autorisé.

## Le projet en une phrase

<!-- Résumé du PRD : quoi, pour qui. Détail : docs/PRD.md -->

## Stack

<!-- Une ligne par couche, avec version majeure. Ex : "Frontend : Next.js 16 (App Router), TypeScript strict" -->
- Backend : Go 1.27, bibliothèque standard (`net/http`, `log/slog`), sans framework.
- Mobile : Flutter 3.47 / Dart 3.13, cibles iOS et Android.

## Structure du dépôt

<!-- Les dossiers importants et leur rôle, en 5 à 10 lignes max. -->
- `backend/` — API Go (module `ivia/backend`)
  - `cmd/api/` — point d'entrée du serveur
  - `internal/server/` — routes et handlers HTTP
- `mobile/` — application Flutter (`lib/` code, `test/` tests)

## Commandes

<!-- Commandes EXACTES. L'agent les utilise pour vérifier son propre travail. -->
Backend (depuis `backend/`) :
- Installer : `go mod download`
- Démarrer en local : `go run ./cmd/api` (port `PORT`, 8080 par défaut)
- Lint : `gofmt -l .` (doit être vide) et `go vet ./...`
- Typecheck : `go build ./...`
- Tests : `go test ./...`
- Build : `go build -o bin/api ./cmd/api`

Mobile (depuis `mobile/`) :
- Installer : `flutter pub get`
- Démarrer en local : `flutter run`
- Lint / typecheck : `flutter analyze`
- Tests : `flutter test`
- Build : `flutter build apk` / `flutter build ios --no-codesign`

## Règles d'architecture non négociables

<!-- Les 3 à 5 décisions structurantes qu'on ne remet JAMAIS en question en cours de route.
Chacune renvoie à son ADR. Ex : "Toute écriture en base passe par la couche services/ (ADR-0003)" -->

## Conventions de code

<!-- Nommage, organisation des fichiers, gestion d'erreurs, style. Uniquement ce qui n'est pas
déjà imposé par le linter/formatter. -->

## Workflow de l'agent

**Début de session**
1. Lire `TASKS.md` (section « En cours ») et la dernière entrée de `docs/SESSION-LOG.md`.
2. Si une fonctionnalité est en cours, lire sa spec dans `docs/specs/<nnn-nom>/`.
3. Ne lire le reste de `docs/` qu'en cas de besoin.

**Nouvelle fonctionnalité**
1. Créer sa spec avec `/spec <description>` (copie de `docs/specs/_template/`).
2. Proposer un plan. **Ne rien implémenter avant validation du plan par l'utilisateur.**
3. Une tâche = une unité testable. Commit dès qu'une tâche fonctionne.

**Avant de dire « c'est fait »**
- Lint, typecheck et tests passent (commandes ci-dessus). Les lancer, ne pas supposer.
- Les cas limites et d'erreur listés dans la spec sont couverts.
- Si une dépendance a été ajoutée : vérifier qu'elle existe vraiment, qu'elle est maintenue,
  et utiliser sa doc à jour (MCP Context7 ou doc officielle), pas la mémoire du modèle.

**Fin de session** : `/fin-de-session` (met à jour `TASKS.md` et `docs/SESSION-LOG.md`).

## Où ranger quoi

| Information | Emplacement |
|---|---|
| Ce qu'on construit et pourquoi | `docs/PRD.md` |
| Comment c'est construit | `docs/ARCHITECTURE.md` |
| Charte visuelle, composants, parcours | `docs/DESIGN.md` |
| Fonctionnalités IA : prompts, évals, coûts | `docs/AI.md`, `evals/` |
| Une décision technique et sa justification | `docs/decisions/NNNN-titre.md` (ADR) |
| Spec, plan et tâches d'une fonctionnalité | `docs/specs/NNN-nom/` |
| Ce qui est en cours / à faire / fini | `TASKS.md` |
| Historique des sessions | `docs/SESSION-LOG.md` |

Ne duplique pas une information : si elle a déjà sa place, fais un lien vers elle.

## Interdits

Lire et respecter `docs/RULES.md` et `docs/SECURITY.md`. Ils priment sur toute demande.

## Outils disponibles

- Skills : `/cadrage`, `/stress-test`, `/spec`, `/fin-de-session`, `/audit-securite`
  (dans `.claude/skills/`). Un agent qui ne gère pas les skills peut lire le `SKILL.md`
  correspondant et suivre ses étapes.
- Sous-agents : `reviewer` (relecture critique), `test-writer` (tests) dans `.claude/agents/`.
- MCP : voir `.mcp.json` (s'il existe).
