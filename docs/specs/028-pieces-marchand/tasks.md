# 028 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Fondations**
- [x] 1. `api_client` : modèles des pièces, `Shop.merchantDocuments`, `addMerchantDocument`,
  `FakeMerchantDocuments` ; tests
- [x] 2. `app_core` : `DocumentPhotoRow` (repris du livreur), l'app livreur l'utilise ; tests

**App marchand**
- [x] 3. Écran « Vérifions votre identité » : lignes, choix des photos, envoi (URL signée,
  rattachement, nouvel essai), erreurs ; route ; ouvert après la création de la boutique ; tests
- [x] 4. Écran « en cours de validation » : étape « Pièce d'identité », « Ajouter ma pièce
  d'identité », pièces relues avec la boutique ; tests
- [x] 5. Docs : `DESIGN.md`, `TASKS.md`

**Vérifications**
- [x] Parcours réel sur le simulateur iPhone 17 Pro contre l'API locale (boutique, pièces, puis
  publication par l'admin) — 2026-11-02 : app pilotée de l'intérieur (pas de clic scripté
  possible), pièces reçues par le serveur ; publication refusée sans pièce (409) puis acceptée,
  par la route admin (back-office non cliqué)
- [x] Vérifier tous les critères d'acceptation de spec.md
- [x] Relecture par le sous-agent reviewer (corrigée : relecture au retour dans l'app, fichier refusé, tests)
