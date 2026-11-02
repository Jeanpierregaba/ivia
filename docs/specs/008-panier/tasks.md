# 008 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Fondations**
- [x] 1. `api_client` : `Cart`, `CartItem`, méthodes du panier, `FakeCart` fidèle au module `cart`,
  tests
- [x] 2. `ui` : « + » des cartes produit, icône à badge, tests (sémantique, police à 200 %)

**App acheteur**
- [x] 3. `cartProvider` et ajout (`addToCart`) : cumul des quantités, feuille « Vider le panier
  ? », messages d'erreur du serveur, remise à zéro au changement de compte ; tests
- [x] 4. Icône du panier (accueil, fiches), « Ajouter » de la fiche produit, « + » des cartes et
  de la fiche boutique, barre « Voir le panier » ; tests
- [x] 5. Écran Panier : boutique, lignes et quantités (une requête à la fois par ligne), retrait
  avec « Annuler », lignes en erreur, boutique fermée, « Vider », vide, réseau coupé,
  « Commander » annoncé pour la 009 ; tests
- [x] 6. Docs : `DESIGN.md`, `TASKS.md`

**Vérifications**
- [ ] Parcours réel sur le simulateur iPhone 17 Pro contre l'API locale
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
