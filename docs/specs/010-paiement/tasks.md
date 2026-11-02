# 010 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Serveur** (partie critique : test d'abord, relu par Gedeon)
- [x] 1. Tests Go de l'annulation et de la limite des demandes (échouent)
- [x] 2. `POST /v1/payments/{id}/cancel` et limiteur de `Initiate` ; `openapi.yaml`, types du
  back-office régénérés ; tests verts

**Fondations mobiles**
- [x] 3. `api_client` : modèle `Payment`, méthodes, `FakePayments` ; `app_core` : `maskedPhone`,
  `countdown` ; tests

**App acheteur**
- [x] 4. Écran Paiement : montant, opérateurs, numéro du profil, « Payer », erreurs ; routes ;
  « Payer » de l'écran Commande et du suivi y mènent ; tests
- [x] 5. Écran d'attente : texte, temps restant, relecture toutes les 3 s, succès, échec, délai
  dépassé ; tests
- [x] 6. « Je n'ai rien reçu », « Annuler le paiement », simulation locale ; tests
- [x] 7. Docs : `DESIGN.md`, `AGENTS.md`, `TASKS.md`

**Vérifications**
- [ ] Parcours réel sur le simulateur iPhone 17 Pro contre l'API locale (commande, paiement
  simulé depuis l'app, refus, annulation, code de remise)
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
