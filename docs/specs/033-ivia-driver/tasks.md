# 033 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Serveur (poussé tôt, relu par Gedeon)**
- [x] 1. Zones de travail dans `GET /v1/driver/options` :
      - lues par le service `mapping` ;
      - test de bout en bout (actives seulement) ;
      - `openapi.yaml`, types du back-office.

**Socle**
- [x] 2. Nom « Ivia Driver » :
      - Android, iOS, titre, identité (badge « Driver ») ;
      - splash natif régénéré ;
      - `mobile/README.md`, outil d'aperçu ;
      - tests mis à jour.
- [x] 3. Charte : `driver_colors.dart` dans `packages/ui`, `common/ui.dart` et `common/formats.dart`.
      Tests des composants :
      - glissière : agit au bout, revient au départ sinon ;
      - barre du bas claire, onglet actif ;
      - cases de code.
- [x] 4. `api_client` :
      - options (véhicules, pièces, zones), activité, compte de versement, envoi ;
      - `DriverDossier` complété ;
      - historique paginé sur 62 jours ;
      - `alertSound` facultatif dans `registerPushToken` (pharmacie ; Ivia Driver n'a pas de push) ;
      - faux serveur et tests.

**Lancement et inscription**
- [x] 5. Splash D00 et présentation D01 à D03 (illustrations, « Passer », retour, « Commencer »).
- [x] 6. Connexion D04 et code D05 par numéro (identité de l'app). Tests : aucun champ e-mail,
      parcours jusqu'au dossier.
- [x] 7. Dossier D06 :
      - véhicule, plaque sauf vélo, marque et modèle, zone, pièces selon le véhicule, compte de
        versement ;
      - envoi bloqué tant qu'il manque quelque chose ;
      - erreurs du serveur.
- [x] 8. En vérification D07 ; dossier refusé ou suspendu et récapitulatif restylés.

**Travail**
- [x] 9. Barre du bas claire et accueil hors ligne D08 :
      - salutation, carte du jour (calculée) ;
      - glisser pour passer en ligne.
- [x] 10. Accueil en ligne D09 : bandeau « En ligne · depuis », « Pause », carte ou fond neutre,
      volet « Recherche de missions… ».
- [x] 11. Mission proposée D10 : gain, compte à rebours, trajet, glisser pour accepter, refuser,
      proposition expirée ou prise.
- [x] 12. Vers le retrait D11 et vers le client D13 :
      - itinéraire dans l'app de navigation choisie ;
      - heure d'arrivée estimée (calcul testé) ;
      - appel ;
      - glisser à l'arrivée.
- [x] 13. Tests du retrait et de la preuve de remise, écrits avant le code (parties critiques) :
      - boutique : cases du colis, puis glisser « récupéré » ;
      - pharmacie : code affiché, pas de glissière, passage seul après la validation, montant
        avancé ; ancienne course sans code ;
      - preuve : 4 chiffres, case ordonnance, code faux effacé.
- [x] 14. Retrait D12 (boutique et pharmacie, relecture toutes les 5 s pendant l'attente).
- [x] 15. Preuve de remise D14 et livraison terminée D15 (rester en ligne, faire une pause).
- [ ] 16. Un problème ? D16 : client injoignable (attente et appels, refus du serveur affiché),
      appel au support pour les autres situations.

**Onglets**
- [ ] 17. Missions D17 : recherche par numéro, onglets « En cours · n », « Terminées », « Annulées »,
      cartes, état vide.
- [ ] 18. Gains D18 :
      - calcul testé : jours de Lomé, semaine, mois, variation ;
      - barres, liste par jour ;
      - compte de versement masqué.
- [ ] 19. Profil D19 :
      - véhicule, documents, zone ;
      - application de navigation, sonnerie des missions (son et vibration à l'arrivée d'une
        proposition, réglage du téléphone) ;
      - aide, déconnexion.

**Finitions**
- [ ] 20. Police à 200 % sur 320 dp pour tous les écrans (220 % sur les lignes à montants) ; ancien
      code supprimé (`work_screens.dart`, écrans remplacés) ; lint et analyse.
- [ ] 21. Vérification sur le simulateur iPhone, avec l'API locale et `seed-demo`, écran par écran
      face aux maquettes.
      - `TASKS.md` : 033, tâche 20 de la 032 renvoyée vers la 033, manques serveur pour Gedeon.
      - `docs/DESIGN.md` : charte Ivia Driver.
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
