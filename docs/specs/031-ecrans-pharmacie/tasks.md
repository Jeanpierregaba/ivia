# 031 — Tâches

<!-- Ordonnées. Chaque tâche est petite, testable et committable seule. Cochée dès qu'elle est faite et commitée. -->

**Socle**
- [x] 1. Découper `shell.dart`, `application_screen.dart` et `ui.dart` en dossiers par
      fonctionnalité, sans changer le comportement. Ajouter `test/helpers.dart`. Les tests actuels
      restent verts.
- [x] 2. Ajouter la palette `IviaPharmacyColors` (`packages/ui`) et les composants communs
      (`lib/common/`) :
      - `PBackButton`, `PHeader`, `PBottomBar` ;
      - `PCountdown`, qui passe à « Terminée » à zéro ;
      - `PCheckRow`, `PSwitchRow`, `PEmpty`, `PErrorRetry` ;
      - avec leurs tests.

**Lancement**
- [x] 3. Splash F00 : tuile, logotype vert et groupe centré (`IviaSplashTile`, `centerGroup`), splash natif vert.
- [x] 4. Présentation en 3 pages, avec ses illustrations (le retour existait déjà dans
      `IviaOnboarding`. Route placée après la localisation et montrée une fois.
- [x] 5. Connexion F04 et code F05 : options facultatives d'`AppIdentity` (conditions
      partenaires, titre selon le canal, « Valider »). Un test vérifie que l'acheteur ne change pas.

**Dossier**
- [x] 6. Cadre des 5 étapes (en-tête, pastille « n sur 5 », retour, reprise d'un brouillon).
      Étape 1 (fiche et photo de devanture) et étape 2 (carte), puis création et envoi de la photo.
- [x] 7. Étape 3 : pièces et case « Je certifie… ». La devanture est redemandée si son envoi a
      échoué.
- [x] 8. Étapes 4 et 5 :
      - planning, qu'on peut passer ;
      - compte de versement ;
      - « Envoyer pour validation » grisé tant qu'il manque quelque chose ;
      - motif des compléments demandés.
- [x] 9. F08 : anneau, frise à 4 étapes, « Préparer mon planning de garde », actualisation en
      tirant, pharmacie suspendue.

**Espace pharmacie**
- [x] 10. Barre flottante à 4 onglets (pilule verte, pastille des alertes non vues). Accueil F09 :
      - en-tête vert ;
      - interrupteur « En service » ;
      - chiffres du jour ;
      - alertes à traiter ;
      - carte des commandes à préparer.
- [x] 11. Alerte entrante F10 :
      - route `incoming/:id` ;
      - « Voir l'alerte » et « Ignorer » ;
      - branchement du push (`onAlertReceived` avec l'identifiant) ;
      - relecture sans Firebase, une seule fois par alerte.
- [x] 12. Détail F11 :
      - ordonnance, produits, générique accepté, précision du client ;
      - compte à rebours ;
      - « Alerte terminée ».
- [x] 13. Ordonnance F12 :
      - pages, zoom (doigt et boutons), pivot ;
      - canal `FLAG_SECURE` dans `MainActivity` et son test ;
      - mention Android seulement.
- [x] 14. Réponse F13 :
      - disponible, prix, quantité, générique, « sur ordonnance » ;
      - total indicatif et « n / N » ;
      - ajout de produits pour une ordonnance en photo seule ;
      - puis F14 « Réponse envoyée ».
- [ ] 15. Commande en retrait :
      - F15 et « Produits mis de côté » ;
      - remise F16 (4 cases, cases à cocher, code faux) ;
      - succès « Commande remise au client ».
- [ ] 16. Commande en livraison :
      - F17 (paiement, 3 étapes, « Recherche d'un livreur ») ;
      - « Marquer prête » ;
      - F19 « Commande remise au livreur ».
- [ ] 17. Feuille F18 « Annuler cette commande ? » : motifs, « Autre motif » avec texte libre,
      « Garder la commande ».
- [ ] 18. Onglet Alertes F21 (En cours, Commandes, Historique par jour) et onglet Commandes, avec
      leurs états vides.
- [ ] 19. Planning F20 :
      - bande de la semaine et points des gardes ;
      - « + » pour ajouter ;
      - import ;
      - carte bleue ;
      - heures de nuit.
- [ ] 20. Relevé F22 : solde, « 0 % de commission », commandes livrées, compte de versement.
- [ ] 21. Profil F23 :
      - Informations (`updatePharmacyContact`, ouverte 24 h/24, de garde) ;
      - Documents ;
      - Planning ;
      - Relevé ;
      - aide ;
      - déconnexion.
- [ ] 22. Sonnerie des alertes par téléphone : deux canaux Android, réglage lu au premier plan
      comme en arrière-plan, et iOS sans son.

**Finitions**
- [ ] 23. Passe d'accessibilité : chaque écran en 320 dp à 200 %, libellés du lecteur d'écran.
      Habiller l'écran d'autorisation des alertes à la charte.
- [ ] 24. Vérification sur le simulateur iPhone 17 Pro, écran par écran contre les maquettes
      (`seed-demo`). Sur Android si un émulateur est disponible : F10 plein écran, sonnerie,
      blocage de capture.
- [ ] 25. `TASKS.md` : manques notés pour Gedeon (liste de la spec et opérateur du versement,
      compteurs du jour). Retirer les écrans et fichiers devenus inutiles.
- [ ] Vérifier tous les critères d'acceptation de spec.md
- [ ] Relecture par le sous-agent reviewer
