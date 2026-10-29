---
name: spec
description: Démarre une nouvelle fonctionnalité en spec-driven development - crée docs/specs/NNN-nom/ avec spec, plan technique et liste de tâches, à valider avant tout code. À utiliser dès que l'utilisateur veut ajouter une fonctionnalité non triviale.
argument-hint: "<description de la fonctionnalité>"
---

# Nouvelle fonctionnalité : $ARGUMENTS

Ne code rien tant que les trois étapes ci-dessous ne sont pas validées par l'utilisateur.

## 0. Préparer
- Numéro : le plus grand `NNN` existant dans `docs/specs/` + 1 (commence à `001`).
- Copie `docs/specs/_template/` vers `docs/specs/NNN-nom-court/` (nom en kebab-case).
- Relis `docs/PRD.md`, `AGENTS.md` et les ADR concernés pour rester cohérent.

## 1. Spec → `spec.md` (le QUOI)
Remplis le fichier. Pose les questions nécessaires (4 max à la fois) pour lever les ambiguïtés.
Les critères d'acceptation doivent être vérifiables par un test. Fais valider.

## 2. Plan → `plan.md` (le COMMENT)
Fichiers touchés, modèle de données, API, composants, dépendances éventuelles (vérifiées : elles
existent, sont maintenues, doc à jour). Si une décision est structurante, crée un ADR.
Pour une fonctionnalité risquée, applique la skill `stress-test` sur la spec et le plan.
Fais valider.

## 3. Tâches → `tasks.md`
Découpe en tâches de quelques dizaines de minutes, chacune testable et committable seule, dans
l'ordre d'exécution. Pour les parties critiques (voir `docs/TESTING.md`), la tâche « écrire le
test » précède la tâche d'implémentation.

## 4. Lancer
- Ajoute la fonctionnalité dans « En cours » de `TASKS.md` avec un lien vers la spec.
- Implémente tâche par tâche : après chacune, lance lint / typecheck / tests, coche la tâche,
  propose un commit.
- À la fin : vérifie chaque critère d'acceptation, fais relire par le sous-agent `reviewer`,
  puis déplace la ligne dans « Terminé ».
