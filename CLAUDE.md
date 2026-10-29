@AGENTS.md

<!--
Les instructions du projet vivent dans AGENTS.md (lu par tous les agents).
N'ajoute ici que ce qui est spécifique à Claude Code.
-->

## Spécifique à Claude Code

- Pour une tâche complexe, utilise le mode plan avant d'éditer.
- Délègue la relecture au sous-agent `reviewer` avant de déclarer une fonctionnalité terminée.
- Les hooks de `.claude/settings.json` bloquent l'écriture des fichiers sensibles et formatent
  le code après chaque modification : ne cherche pas à les contourner.
