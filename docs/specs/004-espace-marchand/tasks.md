# 004 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

- [x] 1. Backend : catégories de boutique (migration 00019, `GET /v1/shop-categories`,
      `category_id` obligatoire à la création, openapi.yaml, données de démonstration) ; tests Go
- [x] 2. `packages/app_core` : déplacer la connexion de l'acheteur (contrôleur, parcours, écrans,
      utilitaires) et la paramétrer ; tests de l'acheteur verts sans changement visible
- [ ] 3. `ui` : couleurs d'action par app, `IviaTheme.light(brand)`, splash tuile + sous-titre,
      `IviaStepList`, `IviaSelectField` ; tests et contrastes
- [ ] 4. `api_client` : catégories, quartiers, boutiques, envoi de fichier par URL signée ; tests
- [ ] 5. Marchand : splash de chargement, présentation et illustrations ; tests
- [ ] 6. Marchand : connexion (« Espace marchand », encart du code) et `SellerSession` + routeur ;
      tests
- [ ] 7. Marchand : « Créez votre boutique » sans carte (champs, catégories, quartiers, téléphone,
      consentement, envoi) ; tests
- [ ] 8. Marchand : logo (choix, compression sans métadonnées, envoi signé) ; tests
- [ ] 9. Marchand : position (carte Google Maps si activée, sinon aperçu ; « Ma position ») ;
      permissions ; tests
- [ ] 10. Marchand : « En cours de validation », refus / suspension, accueil et produits
      provisoires ; tests
- [ ] 11. Vérification sur le simulateur iPhone 17 Pro contre l'API locale (validation par l'admin)
- [ ] 12. Docs : DESIGN.md, ARCHITECTURE.md, AGENTS.md, TASKS.md
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
