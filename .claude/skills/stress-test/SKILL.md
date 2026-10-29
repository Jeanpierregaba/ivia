---
name: stress-test
description: Relecture critique des documents de cadrage ou d'une spec pour trouver ce qui va casser, les cas limites oubliés et le sur-engineering. À utiliser après avoir rédigé PRD/ARCHITECTURE, ou sur une spec avant de l'implémenter.
argument-hint: "[fichier(s) à challenger, par défaut PRD + ARCHITECTURE + DESIGN]"
---

# Stress-test

Cible : $ARGUMENTS (par défaut `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN.md`).

Lis la cible en entier, puis réponds en jouant l'avocat du diable — un développeur senior qui doit
maintenir ce projet pendant 2 ans. Classe chaque point par gravité (bloquant / important / mineur).

1. **Ce qui va casser** : points de défaillance, dépendances fragiles, limites de services tiers
   (quotas, coûts, verrouillage), montée en charge.
2. **Cas limites oubliés** : données vides, doublons, accès concurrents, utilisateur supprimé,
   paiement échoué, fuseau horaire, hors ligne, gros volumes, caractères spéciaux.
3. **Sécurité** : passe en revue `docs/SECURITY.md` au regard de cette architecture.
4. **Sur-engineering** : ce qui est trop complexe pour un MVP et peut être simplifié ou reporté.
5. **Contradictions** entre les documents (PRD ↔ architecture ↔ design).
6. **Questions ouvertes** que l'utilisateur doit trancher.

Ensuite, propose les modifications concrètes à apporter aux fichiers. **N'applique qu'après
validation**, puis résume les risques acceptés dans « Points d'attention » d'ARCHITECTURE.md
(ou dans la spec si la cible est une spec).
