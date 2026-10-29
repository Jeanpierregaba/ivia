# ivia

<!-- Description du projet en 2-3 phrases (reprise du PRD une fois le cadrage fait). -->

## Démarrer

<!-- Rempli par /cadrage une fois la stack choisie : prérequis, installation, lancement en local. -->

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
