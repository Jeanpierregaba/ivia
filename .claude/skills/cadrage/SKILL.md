---
name: cadrage
description: Cadrage complet d'un nouveau projet avant tout développement. Interroge l'utilisateur et remplit PRD, architecture, design, règles, sécurité, tests, backlog et outillage. À utiliser au démarrage d'un projet, ou quand AGENTS.md indique "Statut du cadrage : NON FAIT" et que l'utilisateur veut commencer à coder.
argument-hint: "[étape à reprendre, optionnel]"
---

# Cadrage du projet

Tu mènes un entretien de cadrage puis tu remplis les fichiers du projet. L'utilisateur n'est pas
forcément développeur : explique tes propositions simplement et justifie chaque choix technique.

## Règles de l'entretien

- Pose **au plus 4 questions à la fois**, regroupées par thème. Propose des réponses par défaut
  raisonnables pour que l'utilisateur puisse simplement valider.
- Après chaque étape : écris le fichier, montre un résumé en 3-5 lignes, demande validation avant
  de passer à la suivante.
- Remplace les commentaires `<!-- ... -->` d'instruction par le vrai contenu. Garde la structure
  des titres. Si une section ne s'applique pas, écris « Sans objet — <raison> ».
- **Reprise** : commence par regarder quels fichiers sont déjà remplis et reprends à la première
  étape non terminée (ou à celle indiquée en argument : $ARGUMENTS). Annonce où tu reprends.
- Ne code aucune fonctionnalité pendant le cadrage.

## Étapes

### 1. Produit → `docs/PRD.md`
Problème, utilisateurs, parcours principaux, fonctionnalités du MVP (une ligne testable chacune),
hors scope, vocabulaire du domaine, critères de succès, contraintes (budget, délai, RGPD, appareils).
Pousse l'utilisateur à **réduire** le MVP : ce qui n'est pas indispensable va dans « Hors scope ».

### 2. Architecture → `docs/ARCHITECTURE.md` + ADR
- Propose une stack adaptée au PRD et au niveau de l'utilisateur, avec 1 alternative et les compromis.
  Privilégie des technologies répandues et bien documentées (l'agent les maîtrise mieux).
- **Vérifie les versions actuelles** et les commandes d'installation dans la doc officielle
  (MCP Context7 ou recherche web) : ne te fie pas à ta mémoire.
- Une fois validée : remplis ARCHITECTURE.md et crée `docs/decisions/0001-choix-de-la-stack.md`
  à partir de `docs/decisions/0000-template.md`. Un ADR par autre décision structurante
  (base de données, auth, hébergement…).

### 3. Design → `docs/DESIGN.md`
Intention, design system, écrans principaux, accessibilité, responsive, ton.
Si le projet n'a pas d'interface : supprime DESIGN.md et sa ligne dans AGENTS.md.

### 4. Stress-test
Applique la skill `stress-test` sur PRD + ARCHITECTURE + DESIGN. Intègre les corrections validées
et résume les risques restants dans « Points d'attention » d'ARCHITECTURE.md.

### 5. Instructions de l'agent → `AGENTS.md`
Remplis : le projet en une phrase, stack, structure du dépôt, commandes, règles d'architecture non
négociables (avec liens ADR), conventions de code. Reste concis : ce fichier est lu à chaque session.

### 6. Garde-fous → `docs/RULES.md`, `docs/SECURITY.md`, `docs/TESTING.md`
- RULES : ajoute les interdits spécifiques au projet.
- SECURITY : adapte la checklist à la stack (ex : RLS si Supabase), supprime l'inapplicable en
  justifiant.
- TESTING : outils de test, fonctionnalités critiques en TDD, ce que la CI vérifie.

### 7. Backlog → `TASKS.md`
Une ligne par fonctionnalité du MVP, ordonnées par dépendance puis valeur. La première doit
être petite et livrable rapidement (souvent : squelette déployable + auth).

### 8. Outillage
- `.claude/hooks/format.mjs` (s'il existe) : renseigne `FORMAT_COMMAND` avec le formateur de la stack.
- `.github/workflows/ci.yml` (s'il existe) : remplace l'étape d'avertissement par les vraies étapes
  install / lint / typecheck / test / build, avec les versions vérifiées.
- `.env.example` : les variables nécessaires, sans valeur, commentées.
- `.mcp.json` : propose les serveurs MCP utiles à cette stack (base de données, hébergeur…).
  N'ajoute que des serveurs officiels ou largement reconnus, et explique à quoi chacun sert.
- `README.md` : section « Démarrer ».

### 9. Squelette → `src/` (ou l'emplacement prévu par la stack)
Initialise le projet avec l'outil officiel de la stack, crée la structure de dossiers décrite
dans ARCHITECTURE.md avec des fichiers quasi vides. Vérifie que lint, typecheck, tests et build
passent sur ce squelette vide. Supprime `src/README.md` s'il n'est plus utile.

## Fin du cadrage

1. Dans AGENTS.md, remplace « **NON FAIT** » par « **FAIT (AAAA-MM-JJ)** ».
2. Ajoute une entrée dans `docs/SESSION-LOG.md`.
3. Propose un commit : `chore: cadrage initial du projet`.
4. Indique la prochaine étape : `/spec` sur la première fonctionnalité de TASKS.md.
