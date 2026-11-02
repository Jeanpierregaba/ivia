# 028 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Fondations**
- [x] 1. `api_client` : modèles des pièces, `Shop.merchantDocuments`, `addMerchantDocument`,
  `FakeMerchantDocuments` ; tests
- [x] 2. `app_core` : `DocumentPhotoRow` (repris du livreur), l'app livreur l'utilise ; tests

**App marchand**
- [x] 3. Écran « Vérifions votre identité » : lignes, choix des photos, envoi (URL signée,
  rattachement, nouvel essai), erreurs ; route ; ouvert après la création de la boutique ; tests
- [ ] 4. Écran « en cours de validation » : étape « Pièce d'identité », « Ajouter ma pièce
  d'identité », pièces relues avec la boutique ; tests
- [ ] 5. Docs : `DESIGN.md`, `TASKS.md`

**Vérifications**
- [ ] Parcours réel sur le simulateur iPhone 17 Pro contre l'API locale (boutique, pièces, puis
  publication par l'admin dans le back-office)
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
