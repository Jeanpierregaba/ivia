# 011 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

- [x] 1. `api_client` : modèle `SellerOrder` (+ `OrderItem.stockMode`) et routes marchand
      (`sellerOrders`, `sellerOrder`, `acceptOrder`, `rejectOrder`, `startPreparingOrder`,
      `markOrderReady`, `handOverOrder`), tests du client.
- [x] 2. `api_client` : faux serveur `FakeSellerOrders` fidèle au module `orders` (transitions,
      `invalid_transition`, délai de 15 min, 5 essais de code, `handover_locked`, filtres,
      pagination, pannes) et ses tests.
- [x] 3. `ui` : `IviaCountdown` et pastille `IviaNavItem.badge`, tests (défilement, ton,
      `onExpired`, « 9+ », lecteur d'écran).
- [x] 4. `app_core` : libellés de commande communs déplacés de l'app acheteur ; suite acheteur
      verte.
- [x] 5. App marchand : `sellerOrdersProvider` / `sellerOrderProvider`, relecture toutes les 30 s
      dans le cadre (premier plan seulement), pastille de l'onglet Commandes ; tests de relecture.
- [x] 6. App marchand : onglet Commandes (Nouvelles / En cours / Terminées, compteurs, comptes à
      rebours, vides, tirer pour actualiser, « Afficher plus ») ; routes `/orders?tab=…`.
- [x] 7. App marchand : détail d'une commande (articles, stock non suivi, montants, statut,
      compte à rebours, relecture) et actions accepter / préparer / prête, avec les erreurs
      (réseau, `invalid_transition`, 404, `shop_suspended`, double appui, délai dépassé).
- [x] 8. App marchand : feuille de refus (motifs, « Autre » 200 caractères).
- [x] 9. App marchand : écran « Code de remise » (essais restants, `handover_locked`, code jamais
      gardé).
- [x] 10. App marchand : Accueil (résumé nouvelles / en cours, vide, navigation).
- [x] 11. Police à 200 % sur 320 dp et lecteur d'écran sur tous les nouveaux écrans ;
      `docs/DESIGN.md` ; points backend dans `TASKS.md`.
- [x] 12. Vérification sur le simulateur contre l'API locale (commande acheteur → traitée par le
      marchand jusqu'à « Retirée »).
- [x] Vérifier tous les critères d'acceptation de spec.md
- [x] Relecture par le sous-agent reviewer
