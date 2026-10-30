# ivia

Plateforme e-commerce à Lomé : l'acheteur trouve un produit près de chez lui, le paie par Mobile
Money (Flooz, T-Money), puis le retire en boutique ou se le fait livrer par un livreur de la
plateforme. Une API Go, trois apps Flutter (acheteur, marchand, livreur) et un back-office Next.js.

## Démarrer

**Prérequis** : Go 1.27 (la version exacte est téléchargée automatiquement d'après `backend/go.mod`),
Docker Desktop, [sqlc 1.31](https://docs.sqlc.dev) pour régénérer le code SQL.

```bash
# 1. Base de données PostgreSQL + PostGIS (port 5432 ; POSTGRES_PORT=5434 si le port est pris)
docker compose up -d --wait

# 2. API (depuis backend/) — migrations appliquées au démarrage
cd backend
export APP_ENV=local             # obligatoire : local | test | staging | production
export DATABASE_URL="postgres://ivia@localhost:5432/ivia?sslmode=disable"
go run ./cmd/manage seed-dev     # comptes et boutique de démonstration
go run ./cmd/api                 # http://localhost:8080/health

# 3. Tests (contre la base Docker)
go test ./...
```

En local, tout fonctionne sans compte externe : les codes de connexion s'affichent dans les journaux
de l'API (et `POST /v1/dev/otp`, routes `/v1/dev` ouvertes en local et test seulement), les paiements passent par un faux prestataire
(`POST /v1/dev/payments/{id}/simulate`), les fichiers sont stockés sur le disque. Documentation interactive : http://localhost:8080/docs. Le contrat de
l'API est dans [`backend/api/openapi.yaml`](backend/api/openapi.yaml) et les variables dans
[`.env.example`](.env.example).

---

## Méthode de travail

Ce projet suit un cadrage pour le développement avec agent de code.

**1. Cadrer avant de coder.** Ouvre le projet avec ton agent et lance :

```
/cadrage
```

L'agent te pose les questions et remplit dans l'ordre : `docs/PRD.md` → `docs/ARCHITECTURE.md`
(+ ADR) → `docs/DESIGN.md` → stress-test → `AGENTS.md` → `docs/RULES.md`, `docs/SECURITY.md`,
`docs/TESTING.md` → `TASKS.md` → outillage (CI, hooks, `.env.example`) → squelette de `src/`.
Tu peux t'arrêter et reprendre : `/cadrage` repart de la première étape non terminée.

**2. Une fonctionnalité à la fois.**

```
/spec <description de la fonctionnalité>
```

crée `docs/specs/NNN-nom/` (spec → plan → tâches). Tu valides le plan, l'agent implémente
tâche par tâche, commit à chaque étape qui fonctionne.

**3. Clore chaque session.**

```
/fin-de-session
```

met à jour `TASKS.md` et `docs/SESSION-LOG.md`. Au démarrage suivant, un hook redonne
automatiquement ce contexte à l'agent.

**Avant une mise en production** : `/audit-securite`.

| Fichier | Rôle |
|---|---|
| `AGENTS.md` | Instructions de l'agent (source unique ; `CLAUDE.md` l'importe) |
| `TASKS.md` | Avancement |
| `docs/PRD.md` | Quoi et pourquoi |
| `docs/ARCHITECTURE.md` | Comment |
| `docs/DESIGN.md` | Interface et expérience |
| `docs/RULES.md` | Interdits stricts |
| `docs/SECURITY.md` | Checklist sécurité |
| `docs/TESTING.md` | Définition de « fini » |
| `docs/SESSION-LOG.md` | Historique des sessions |
| `docs/decisions/` | Décisions techniques (ADR) |
| `docs/specs/` | Une spec par fonctionnalité |
| `.claude/` | Skills, sous-agents, hooks et permissions |
| `.mcp.json` | Serveurs MCP du projet |

Une fois le projet lancé, tu peux supprimer cette section du README.
