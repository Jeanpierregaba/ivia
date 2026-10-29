# TESTING — Stratégie de validation

<!--
À REMPLIR avant de développer les fonctionnalités.
Répond à une question : comment sait-on qu'une fonctionnalité est « faite » ?
Plus les vérifications sont automatiques, plus l'agent peut se corriger seul.
-->

## Boucle de retour automatique
<!-- Ce que l'agent lance lui-même après chaque modification. Les commandes exactes sont dans AGENTS.md. -->
- Formatage automatique : hook `PostToolUse` de Claude Code (`.claude/hooks/format.mjs`), ou formatage à l'enregistrement dans l'éditeur
- Lint :
- Typecheck :
- Tests unitaires :
- Tests end-to-end : <!-- ex : Playwright ; l'agent peut aussi piloter le navigateur via le MCP Playwright -->

## Intégration continue
<!-- Ce que la CI (.github/workflows/ci.yml) vérifie à chaque push / pull request. Aucun merge si elle échoue. -->

## Ce qui doit être testé pour chaque fonctionnalité
- Cas nominal
- Cas limites (vide, très long, caractères spéciaux, doublons, concurrence)
- Cas d'erreur (réseau, permissions, données invalides)
<!-- Les cas précis de chaque fonctionnalité sont listés dans sa spec (docs/specs/NNN-nom/spec.md). -->

## Fonctionnalités critiques : test écrit AVANT le code
<!-- Les parties où l'exactitude est critique (paiement, auth, droits d'accès, calculs). Pour elles,
l'agent écrit d'abord le test (sous-agent test-writer), vérifie qu'il échoue, puis implémente. -->

## Checklist manuelle avant un commit important
- [ ] Parcours complet testé, pas seulement le chemin heureux
- [ ] Entrées invalides / vides
- [ ] Mobile (si applicable)
- [ ] Mode sombre / accessibilité clavier (si applicable)
