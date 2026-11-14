# 005 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Backend** (commit à part, pour la relecture de Gedeon)
- [x] 1. Tests de bout en bout des états d'un produit :
  - brouillon, publication, retrait, remise en vente, dates ;
  - contrainte de cohérence ;
  - filtres `status` et `q` ;
  - compteurs ;
  - 404 sur la boutique d'autrui.

  Les lancer et vérifier qu'ils échouent.
- [x] 2. Migration `00021` (renumérotée après la 00020 de Gedeon), requêtes sqlc, service et handler (`status`, `q`, `product-counts`),
  `openapi.yaml` ; tests de la tâche 1 au vert, `sqlc diff`, `go vet`, `gofmt`

**Mobile : fondations**
- [x] 3. `api_client` : modèles et méthodes des produits, faux serveur fidèle (filtres,
  compteurs, état), tests
- [x] 4. `app_core` : `formatXof`, `parseXof`, `shortDate`, tests
- [x] 5. `ui` : `IviaBottomNav`, `IviaSegmentedTabs`, `IviaSearchField`, `IviaQuantityStepper`,
  `IviaChoiceCard`, `IviaStatusPill`, tests (sémantique, police à 200 %)

**Mobile : app marchand**
- [x] 6. Shell à 4 onglets, Compte (déconnexion), Commandes « Bientôt disponible », routeur à
  préfixes ; « Préparer mes produits » ouvre le catalogue sans barre ; tests du routeur
- [x] 7. Catalogue :
  - liste par onglet, compteurs, recherche différée, défilement qui charge la suite ;
  - états vides, erreur réseau avec « Réessayer » ;
  - tests.
- [x] 8. Formulaire, étapes 1 et 2 : photos (ajout, principale, suppression), nom, prix,
  catégorie, description, taille, stock ; validations ; abandon confirmé ; tests
- [x] 9. Enregistrement : brouillon, aperçu, publication, écran « Produit publié » (texte selon
  la boutique), reprise d'un brouillon ; envoi des photos réutilisant les clés après un échec ;
  double appui ; tests
- [x] 10. Modifier un produit :
  - carte d'état, feuilles description, taille et stock ;
  - retrait confirmé, puis message avec « Annuler » ;
  - « Remettre » depuis la liste ;
  - catégorie refusée par le serveur ;
  - tests.
- [x] 11. Docs : `DESIGN.md` (catalogue, barre du bas), `ARCHITECTURE.md` (états d'un produit),
  `TASKS.md` (005 et 006)

**Vérifications**
- [x] Parcours réel sur le simulateur iPhone 17 Pro contre l'API locale (création avec photo,
  brouillon, retrait, remise en vente)
- [x] Vérifier tous les critères d'acceptation de spec.md
- [x] Relecture par le sous-agent reviewer : 1 bloquant, 5 importants et 11 mineurs corrigés et
  testés ; reportés : idempotence de la création, bornes du serveur (voir spec, hors périmètre)
