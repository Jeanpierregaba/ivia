# 0007 — Paiement Mobile Money derrière une interface

- **Statut** : Proposé (prestataire à choisir)
- **Date** : 2026-10-30

## Contexte

Les acheteurs paient par Flooz (Moov Africa) ou T-Money (Yas) avant toute exécution de commande.
Un paiement n'est réussi que sur notification serveur du prestataire. L'ouverture d'un compte
marchand demande des documents (RCCM, NIF) et prend du temps.

## Options envisagées

- **Intégration directe des opérateurs** : frais plus bas à grand volume, mais deux intégrations et
  des délais d'ouverture longs et incertains.
- **Agrégateur** couvrant les deux opérateurs : CinetPay, PayDunya, FedaPay, PayGate Global
  (togolais). Commissions annoncées par des sources secondaires : environ 1,5 à 2,2 %, à confirmer
  sur les grilles officielles.

## Décision

Un agrégateur, derrière une interface `PaymentProvider` (initier, vérifier, rembourser, valider un
webhook). Le développement démarre avec un **faux prestataire** qui simule réussite, échec,
attente et expiration. Le choix de l'agrégateur sera acté dans ce document (statut « Accepté »)
après réception des grilles tarifaires officielles et des conditions d'ouverture.

## Conséquences

- **Critère éliminatoire** : transfert d'argent vers un numéro Mobile Money par API (payout), qui
  sert aux remboursements. Sans lui, chaque remboursement (refus marchand, absence de réponse,
  paiement tardif, échec de livraison) se fait à la main hors de la plateforme.
- Autres critères : couverture Flooz + T-Money, frais, webhooks signés, API de vérification de
  statut, environnement de test, délai d'ouverture, possibilité d'encaisser pour le compte des
  marchands dans le respect de la réglementation BCEAO.
- Le webhook est la seule source de vérité ; une tâche de fond revérifie par API les paiements
  restés en attente.
- Les frais du prestataire sont à la charge de la plateforme (pris sur sa commission).
