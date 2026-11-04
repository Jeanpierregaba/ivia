# AGENTS.md — Instructions pour l'agent

<!--
Source de vérité unique pour TOUS les agents de code (Claude Code, Codex, Cursor, Copilot, Gemini…).
CLAUDE.md se contente d'importer ce fichier.

Ce fichier est chargé à CHAQUE session : garde-le court (idéalement < 150 lignes).
Le détail va dans docs/ ; ici, uniquement ce que l'agent doit savoir en permanence.
Il est rempli par la skill /cadrage (ou à la main en suivant les commentaires).
-->

## Statut du cadrage

**FAIT (2026-10-30)** — backend MVP, squelette mobile (3 apps) et back-office en place, voir `TASKS.md`.


> Tant que le statut est « NON FAIT » : si l'utilisateur demande de coder une fonctionnalité,
> propose-lui d'abord de lancer `/cadrage` (ou de suivre `.claude/skills/cadrage/SKILL.md`).
> Un prototype jetable explicitement demandé reste autorisé.

## Le projet en une phrase

Plateforme e-commerce à Lomé : l'acheteur trouve un produit, paie par Mobile Money (Flooz,
T-Money), puis le retire en boutique ou se fait livrer par un livreur de la plateforme.
Trois apps Flutter (acheteur, marchand, livreur), un back-office Next.js, une API Go.
Détail : `docs/PRD.md`.

## Stack

Détail et versions : `docs/ARCHITECTURE.md`.
- Backend : Go 1.27, bibliothèque standard (`net/http`, `log/slog`), monolithe modulaire.
- Données : PostgreSQL 18 + PostGIS 3.6, `pgx/v5`, `sqlc` (requêtes), `goose` (migrations), `River` (tâches de fond).
- Mobile : Flutter 3.47 / Dart 3.13, pub workspace ; Riverpod 3, go_router, dio. Android d'abord.
- Back-office : Next.js 16 (App Router), React 19, TypeScript strict, Tailwind 4, Node 24 LTS, pnpm.
- Services : Mobile Money via agrégateur (à choisir), Brevo (e-mail OTP), FCM (push), Google Maps SDK, Cloudflare R2, Sentry.

## Structure du dépôt

- `backend/` — API Go (module `ivia/backend`)
  - `cmd/api/` — point d'entrée (API + workers River) · `cmd/manage/` — administration (grant-admin, seed-dev)
  - `internal/<module>/` — un dossier par domaine : `queries.sql` (sqlc → `store/`), `service.go`, `handler.go`, `jobs.go`
  - `internal/app/` — assemblage des modules + tests de bout en bout par HTTP
  - `internal/platform/` — config, base (transactions par contexte), HTTP, River, stockage, erreurs, validation
  - `db/migrations/` — migrations goose · `api/openapi.yaml` — contrat de l'API
- `mobile/` — pub workspace : `apps/buyer`, `apps/seller`, `apps/driver`, `packages/api_client`,
  `packages/app_core` (session, connexion, champs communs), `packages/ui`
- `admin/` — back-office Next.js (`app/(admin)/` pages, `lib/api.ts` client serveur de l'API,
  `lib/api-types.ts` généré, `components/`) : voir `admin/README.md`
- `infra/` — déploiement (Compose de production, Caddy, sauvegardes)
- `docker-compose.yml` — services locaux (PostGIS)

## Commandes

<!-- Commandes EXACTES. L'agent les utilise pour vérifier son propre travail. -->
Base de données (depuis la racine) :
- Démarrer : `docker compose up -d --wait` · Arrêter : `docker compose stop`
- Console SQL : `docker compose exec postgres psql -U ivia -d ivia`

Backend (depuis `backend/`) — `APP_ENV=local` et `DATABASE_URL` doivent être exportées (voir `.env.example`) :
- Installer : `go mod download` · outil : sqlc 1.31 (`go install github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1`)
- Démarrer en local : `go run ./cmd/api` (port `PORT`, 8080 par défaut ; codes OTP dans les journaux)
- Données de démonstration : `go run ./cmd/manage seed-dev` · premier admin : `go run ./cmd/manage grant-admin <email>`
- Code SQL généré : `sqlc generate` après toute modification d'un `queries.sql` ou d'une migration (commité)
- Lint : `gofmt -l .` (doit être vide), `go vet ./...`, `sqlc diff` (doit être vide)
- Typecheck : `go build ./...`
- Tests : `go test ./...` (contre PostGIS ; sans `DATABASE_URL`, les tests qui en ont besoin sont ignorés)
- Sécurité : `go run golang.org/x/vuln/cmd/govulncheck@v1.9.0 ./...`
- Build : `go build -o bin/api ./cmd/api`

Back-office (depuis `admin/`, pnpm 10, Node 20.9+ ; Node 24 en CI) :
- Installer : `pnpm install`
- Démarrer en local : `API_BASE_URL=http://localhost:8080 pnpm dev` (http://localhost:3000 ; compte
  `admin@ivia.local` créé par `seed-dev`)
- Types de l'API : `pnpm gen:api` après toute modification d'`openapi.yaml` (fichier commité)
- Lint : `pnpm format:check` et `pnpm lint` · Typecheck : `pnpm typecheck`
- Tests : `pnpm test` · Build : `pnpm build`

Mobile (pub workspace, depuis `mobile/` sauf mention) :
- Installer : `flutter pub get` (un seul `pubspec.lock` pour tout le workspace)
- Démarrer en local : depuis `apps/<buyer|seller|driver>`, `flutter run`
  (`--dart-define=API_BASE_URL=http://…:8080` hors émulateur Android ; simulateur iOS :
  `http://localhost:<PORT>`). Connexion par mot de passe (ADR 0011) : comptes de `seed-dev`
  avec le mot de passe affiché par la commande (local seulement). Code reçu par e-mail
  (création de compte, mot de passe oublié) : journaux de l'API, Mailpit ou `POST /v1/dev/otp` ;
  avec `--dart-define=IVIA_DEV_OTP=true` (build debug, API locale), l'app le lit et le saisit
  seule. Jamais en release : la route n'existe qu'en local et en test. Google : bouton affiché
  seulement avec `--dart-define=GOOGLE_SERVER_CLIENT_ID=…` (client OAuth « web ») et, sur iOS,
  `GOOGLE_IOS_CLIENT_ID=…` plus le schéma d'URL inversé dans `Info.plist`, et si l'API l'annonce
  (`GOOGLE_CLIENT_IDS`). App acheteur :
  `--dart-define=IVIA_DEV_PAYMENT=true` ajoute « Simuler la validation » et « Simuler un refus »
  à l'attente du paiement (faux prestataire du serveur, debug seulement)
- Lint : `dart format --output=none --set-exit-if-changed .`
- Lint / typecheck : `flutter analyze` (tout le workspace)
- Tests : `flutter test` dans chaque membre, ou d'un coup :
  `ok=0; for m in apps/* packages/*; do (cd "$m" && flutter test) || ok=1; done; [ $ok -eq 0 ]`
- Build : depuis `apps/<app>`, `flutter build apk` / `flutter build ios --no-codesign`
- Carte Google Maps (app marchand) : clés restreintes, jamais committées — Android :
  `MAPS_API_KEY=…` dans `apps/seller/android/local.properties` ; iOS : `MAPS_API_KEY = …` dans
  `apps/seller/ios/Flutter/Maps.xcconfig` ; puis `--dart-define=GOOGLE_MAPS=true`. Sans clé :
  aperçu sans fond de carte
- Splash natif : après modification de `apps/<app>/flutter_native_splash.yaml` ou de ses images,
  depuis `apps/<app>`, `dart run flutter_native_splash:create` (fichiers Android et iOS générés, commités)

## Règles d'architecture non négociables

1. **Aucun client ne touche la base** : apps et back-office passent par l'API REST `/v1`
   ([ADR-0003](docs/decisions/0003-back-office-nextjs.md)).
2. **Un module ne lit ni n'écrit les tables d'un autre** : il appelle son service. Couches
   handlers → service → store (sqlc) ([ADR-0004](docs/decisions/0004-monolithe-modulaire-sqlc-goose.md)).
3. **Contrôle d'accès dans le backend, à chaque requête** : rôle (middleware) **et** propriété de
   la ressource (service). Ressource d'autrui ⇒ 404 ([ADR-0006](docs/decisions/0006-authentification-otp-sessions.md)).
4. **Un paiement n'est réussi que sur webhook vérifié** (signature, montant, idempotence), jamais
   sur le retour de l'app ([ADR-0007](docs/decisions/0007-paiement-mobile-money.md)).
5. **Statut de commande modifié uniquement par la machine à états du module `orders`**, qui écrit
   `order_status_events` dans la même transaction (diagramme dans `docs/ARCHITECTURE.md`).
6. **Concurrence garantie par la base** : stock réservé par mise à jour conditionnelle, un seul
   livreur actif par commande et une seule mission par livreur par index uniques partiels.
7. **Services externes derrière une interface Go** avec une implémentation factice pour le local
   et les tests (`PaymentProvider`, `OTPSender`, `PushSender`, `ObjectStore`).

## Conventions de code

- **Langue** : code, noms de tables, routes et codes de statut en anglais (vocabulaire du PRD :
  `shop`, `order`, `delivery_offer`, `settlement`…) ; commentaires, docs et textes affichés en français.
- **Argent** : FCFA entiers (`int64` en Go, `bigint` en SQL, suffixe `_xof`). Jamais de `float`.
- **Dates** : `timestamptz` en UTC en base ; affichage et périodes de règlement en `Africa/Lome`.
- **Identifiants** : `uuid` générés par la base.
- **API** : JSON en `snake_case` ; erreurs au format `{"error": {"code": "...", "message": "..."}}`,
  `code` stable en anglais, `message` en français lisible par l'utilisateur. Toute route est décrite
  dans `backend/api/openapi.yaml` **dans le même commit** (`TestOpenAPICoversAllRoutes` le vérifie).
- **Go** : erreurs enveloppées (`fmt.Errorf("contexte : %w", err)`), `context.Context` en premier
  argument, pas de variable globale mutable, `slog` pour les logs (jamais de code OTP, jeton,
  numéro complet ni donnée de paiement).
- **SQL** : une migration goose par changement, jamais modifiée une fois fusionnée ; requêtes dans
  des fichiers `.sql` lus par sqlc, jamais de SQL construit par concaténation.
- **Flutter** : écrans dans `lib/features/<fonctionnalité>/` ; appels API uniquement via
  `packages/api_client` ; couleurs et styles uniquement via `packages/ui` (charte : `docs/DESIGN.md`).
- **Next.js** : composants serveur par défaut ; appels API uniquement côté serveur ; types
  générés depuis `openapi.yaml`, jamais écrits à la main.
- **Tests** : à côté du code (`*_test.go`, `test/` en Dart, `*.test.ts`).

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
| Fonctionnalités IA : prompts, évals, coûts (aucune au MVP) | `docs/AI.md`, `evals/` |
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
