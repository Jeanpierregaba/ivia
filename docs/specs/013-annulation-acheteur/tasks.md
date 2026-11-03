# 013 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

- [x] 1. `api_client` : `BuyerOrder.paidAt`, `cancelOrder` ; `FakeOrders` : annulation fidèle
      (statuts permis, `cannot_cancel`, stock rendu, 404 pour un autre compte) ; `FakePayments` :
      paiement abouti sur une commande annulée ⇒ `paid_at` et événement ; tests.
- [x] 2. App acheteur : bouton « Annuler la commande » (statuts permis), feuille de confirmation
      (non payée / payée), annulation, suivi « Annulée » avec le remboursement annoncé, liste à
      jour ; tests.
- [x] 3. App acheteur : demande de paiement en attente annulée d'abord ;
      `payment_not_cancellable` ⇒ feuille rouverte avec le montant ; `cannot_cancel` (acceptée,
      expirée) ; réseau ; double appui ; résultat gardé si l'écran est quitté ; tests.
- [x] 4. Police à 200 % sur 320 dp et lecteur d'écran ; `docs/DESIGN.md`.
- [x] 5. Vérification sur le simulateur contre l'API locale (annulation avant et après paiement,
      commande retirée des « Nouvelles » côté marchand).
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
