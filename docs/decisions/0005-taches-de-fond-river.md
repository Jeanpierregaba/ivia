# 0005 — Tâches de fond avec River

- **Statut** : Accepté
- **Date** : 2026-10-30

## Contexte

Plusieurs traitements doivent se produire plus tard ou en dehors de la requête : passer au livreur
suivant si le premier ne répond pas, expirer un paiement en attente, revérifier un paiement dont le
webhook n'est pas arrivé, envoyer les notifications. Ils ne doivent pas être perdus au redémarrage.

## Options envisagées

- **Minuteries en mémoire (goroutines)** : simple, mais tout est perdu au redémarrage.
- **Redis + file (Asynq…)** : robuste, mais un service de plus à héberger et sauvegarder.
- **River** : file de tâches stockée dans PostgreSQL ; une tâche peut être créée dans la même
  transaction que la donnée métier (pas de tâche orpheline ni de tâche oubliée).

## Décision

River 0.50, exécuté dans le même processus que l'API au MVP.

## Conséquences

- Pas de nouveau service à héberger.
- River n'est pas encore en 1.0 : version figée dans `go.mod`, notes de version lues avant chaque
  mise à jour.
- Chaque tâche est idempotente (rejouable sans effet en double).
- Les workers pourront être séparés de l'API (`cmd/worker`) si la charge l'exige.
