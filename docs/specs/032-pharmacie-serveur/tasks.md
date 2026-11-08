# 032 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Décision et données**
- [x] 1. ADR 0014 : paiement en espèces de la pharmacie par le livreur. `TASKS.md` : règlement des
      livreurs à prévoir.
- [x] 2. Migration `00038`, puis `sqlc generate`. **Soumise à Gedeon avant la suite.**

**Serveur**
- [x] 3. Numéro d'alerte : création, boîte, détail, vue client, back-office. Tests Go.
- [x] 4. Quartier du client (`geo.NearestNeighborhood`) dans la boîte et le détail. Test : position
      jamais renvoyée.
- [x] 5. Tests de la remise par code, écrits avant le code (partie critique) :
      - bon code, code faux, 5 essais ;
      - commande d'autrui, état incorrect, case non cochée ;
      - « récupéré » refusé au livreur, mission sans code.
- [x] 6. Remise par code :
      - code tiré à l'acceptation de la course ;
      - route `courier-handover` ;
      - avance enregistrée ;
      - notifications ;
      - `pickup_code` et `cash_advanced_xof` dans la mission du livreur.
- [x] 7. Arrivée estimée du livreur (`delivery.DriverLocation` et module carte), `picked_up_at`,
      `cash_paid_xof` et `refund_fee_xof` dans la commande de la pharmacie.
- [x] 8. Envoi du dossier sans compte de versement ; route `cash-receipts` ; route `today` ; lien de
      la devanture dans `me`.
- [x] 9. Origine des gardes (`source`, `imported_at`) : import par la pharmacie, ajout seul, ajout
      par l'admin.
- [x] 10. Sonnerie par appareil : `alert_sound` à l'enregistrement, son retiré du push iOS.
- [x] 11. `openapi.yaml` complet, `TestOpenAPICoversAllRoutes`, `govulncheck`, lint.

**Back-office**
- [ ] 12. Fiche pharmacie :
      - compte et saisie de versement retirés ;
      - historique gardé ;
      - avance du livreur sur les livraisons ;
      - types régénérés.

**Apps**
- [ ] 13. `api_client` : nouveaux champs et routes, avec leurs tests.
- [ ] 14. Pharmacie, dossier en 4 étapes : compte de versement retiré, envoi depuis le planning.
- [ ] 15. Pharmacie, F17 et remise au livreur :
      - saisie du code et case « payé en espèces » ;
      - erreurs et limite d'essais ;
      - F19 avec l'heure de récupération et le montant payé ;
      - arrivée estimée.
- [ ] 16. Pharmacie, F22 « Encaissements » par jour ; profil mis à jour (ligne « Encaissements »).
- [ ] 17. Pharmacie, nouveaux champs :
      - numéro « #A-n » (cartes, détail, F10, historique, F14) ;
      - quartier (F10, F11) ;
      - forfait (F18) ;
      - devanture (accueil, profil, fiche) ;
      - planning officiel (F20) ;
      - compteurs du serveur (F09).
- [ ] 18. Pharmacie : sonnerie proposée sur iPhone, `alert_sound` envoyé avec le jeton.
- [ ] 19. Pharmacie : pièces en PDF (`file_selector`, dépendance vérifiée) ; libellé « PDF ou photo ».
- [x] 20. (fait dans la [spec 033](../033-ivia-driver/spec.md), tâche 14) Livreur : code de retrait affiché, plus de « Récupéré » pour la pharmacie, montant avancé
      dans la mission et l'historique.
- [ ] 21. Acheteur : numéro d'alerte dans le suivi.

**Finitions**
- [ ] 22. Vérification sur le simulateur avec l'API locale (`seed-demo`) : pharmacie, livreur,
      acheteur. `TASKS.md` mis à jour (manques résolus, règlement des livreurs).
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
