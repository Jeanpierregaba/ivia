# 009 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Fondations**
- [x] 1. `api_client` : modèles de commande, `quoteOrder`, `createOrder`, `myOrders`, `myOrder`,
  `newRequestId`, `FakeOrders` fidèle au module `orders` ; tests
- [x] 2. `ui` et `app_core` : code de remise, frise, `timeOfDay` ; tests (sémantique, police à
  200 %)

**App acheteur**
- [x] 3. Écran Commande : modes (livraison « Bientôt »), boutique, récapitulatif, « Payer »
  (identifiant de requête, double appui, réseau coupé, refus), panier relu ; « Commander » du
  panier y mène ; tests
- [x] 4. Onglet Commandes : en cours / terminées, « Récemment », vides, relecture (ouverture,
  retour, compte) ; tests
- [x] 5. Suivi : en-têtes par statut, code de remise, boutique, frise, articles, relecture toutes
  les 20 s et au retour dans l'app, 404 ; tests
- [x] 6. Docs : `DESIGN.md`, `TASKS.md`

**Vérifications**
- [x] Parcours réel sur le simulateur iPhone 17 Pro contre l'API locale (commande, paiement
  simulé par le serveur, acceptation et « prête » par le marchand, code)
- [x] Vérifier tous les critères d'acceptation de spec.md
- [x] Relecture par le sous-agent reviewer : 1 bloquant (retour pendant « Payer »), 6 importants et
  les mineurs corrigés et testés
