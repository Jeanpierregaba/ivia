# 004 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

- [x] 1. Backend : catégories de boutique (migration 00019, `GET /v1/shop-categories`,
      `category_id` obligatoire à la création, openapi.yaml, données de démonstration) ; tests Go
- [x] 2. `packages/app_core` : déplacer la connexion de l'acheteur (contrôleur, parcours, écrans,
      utilitaires) et la paramétrer ; tests de l'acheteur verts sans changement visible
- [x] 3. `ui` : couleurs d'action par app, `IviaTheme.light(brand)`, splash tuile + sous-titre,
      `IviaStepList` ; tests et contrastes (liste déroulante : `DropdownButtonFormField` de
      Material, pas de composant propre)
- [x] 4. `api_client` : catégories, quartiers, boutiques, envoi de fichier par URL signée ; tests
- [x] 5. Marchand : splash de chargement, présentation et illustrations ; tests
- [x] 6. Marchand : connexion (« Espace marchand », encart du code) et `SellerSession` + routeur ;
      tests
- [x] 7. Marchand : « Créez votre boutique » sans carte (champs, catégories, quartiers, téléphone,
      consentement, envoi) ; tests
- [x] 8. Marchand : logo (choix, compression sans métadonnées, envoi signé) ; tests
- [x] 9. Marchand : position (carte Google Maps si activée, sinon aperçu ; « Ma position ») ;
      permissions ; tests
- [x] 10. Marchand : « En cours de validation », refus / suspension, accueil et produits
      provisoires ; tests
- [x] 11. Vérification sur le simulateur iPhone 17 Pro contre l'API locale (validation par l'admin)
- [x] 12. Docs : DESIGN.md, ARCHITECTURE.md, AGENTS.md, TASKS.md
- [x] Vérifier tous les critères d'acceptation de spec.md (carte Google Maps : vérification manuelle avec les clés)
- [x] Relecture par le sous-agent reviewer (2026-10-31) : 5 points importants et mineurs corrigés
