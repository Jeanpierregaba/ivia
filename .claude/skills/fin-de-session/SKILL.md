---
name: fin-de-session
description: Clôture une session de travail - met à jour TASKS.md, les tasks.md des specs en cours et ajoute une entrée en haut de docs/SESSION-LOG.md. À utiliser quand l'utilisateur dit qu'il s'arrête, ou en fin de journée.
---

# Fin de session

1. **Faire le point** : liste ce qui a été fait pendant la session (conversation + `git log` /
   `git status` depuis le début de la session) et ce qui n'est pas commité.
2. **`TASKS.md`** : déplace ce qui est terminé, mets à jour « En cours », ajoute les nouvelles
   tâches découvertes.
3. **Specs en cours** : coche les tâches faites dans `docs/specs/*/tasks.md`.
4. **Décisions** : si une décision technique a été prise sans ADR, crée-le dans `docs/decisions/`.
5. **`docs/SESSION-LOG.md`** : ajoute en HAUT (sous le commentaire) une entrée au format :

   ```
   ### AAAA-MM-JJ — titre court
   - Fait :
   - Pièges rencontrés :
   - Décisions : (liens vers les ADR)
   - Prochaine étape :
   ```

   « Prochaine étape » doit être assez précise pour qu'une nouvelle session démarre sans question.
6. **Commit** : s'il reste des changements, propose un message de commit (ne committe qu'avec
   l'accord de l'utilisateur).
7. Si une règle ou convention a été découverte pendant la session, propose de l'ajouter à
   `AGENTS.md` ou `docs/RULES.md`.
