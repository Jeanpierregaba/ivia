# 007 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Fondations**
- [x] 1. `app_core` : position partagée (`location.dart`, précision réglable), `formatDistance` ;
  app marchand branchée dessus, ses tests au vert
- [x] 2. `api_client` : modèles et méthodes de recherche et des fiches publiques, `FakeSearch`
  fidèle, tests
- [x] 3. `ui` : puce de filtre, carte produit, carrousel de photos (repris du catalogue marchand),
  tests (sémantique, police à 200 %)

**App acheteur**
- [x] 4. Shell à 4 onglets (Accueil, Recherche, Commandes, Profil), Profil (déconnexion),
  Commandes « Bientôt disponible », routeur à préfixes ; tests du routeur
- [x] 5. Zone de recherche : position (autorisée, refusée, indisponible), choix du quartier
  mémorisé, permissions iOS et Android ; tests
- [ ] 6. Accueil : en-tête de position, salutation, champ, puces de catégories, boutiques autour
  de vous, nouveautés, actualisation, vides et erreurs ; tests
- [ ] 7. Résultats : recherche différée, onglets Produits / Boutiques, filtres (rayon, catégorie,
  prix, en stock), tri, pagination, vide avec « Effacer les filtres », 429 ; tests
- [ ] 8. Fiche boutique (recherche dans la boutique) et fiche produit (photos, disponibilité,
  boutique, colis, « Ajouter » annoncé pour la 008), 404 ; tests
- [ ] 9. Docs : `DESIGN.md`, `ARCHITECTURE.md`, `TASKS.md`

**Vérifications**
- [ ] Parcours réel sur le simulateur iPhone 17 Pro contre l'API locale (position, quartier,
  recherche, filtres, fiches)
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
