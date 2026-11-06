# Progression du projet ivia

> Fichier tenu à jour à chaque étape. Dernière mise à jour : **2026-11-05**.
> Détail des tâches : [`TASKS.md`](TASKS.md) · journal des sessions : [`docs/SESSION-LOG.md`](docs/SESSION-LOG.md).

## En un coup d'œil

| Partie                      | Avancement | État                                                                       |
| --------------------------- | :--------: | -------------------------------------------------------------------------- |
| Backend (API Go)            |  **~95 %** | Complet pour le MVP ; manque le vrai prestataire de paiement (016)         |
| Back-office web (Next.js)   |  **~95 %** | Tous les écrans du MVP faits ; restent les tests navigateur (Playwright)   |
| Apps mobiles (Flutter)      |  **~50 %** | Acheteur jusqu'à la commande en retrait, catalogue marchand, dossier livreur ; paiement et livraison à faire |
| Infrastructure / mise en ligne | **~60 %** | Images Docker, Compose, Caddy, sauvegardes, CI prêts ; serveurs à louer |
| Publicité IVI / marketing   |  **~90 %** | API, back-office, jeu de démo et app acheteur faits ; reste à saisir les prix IVI |
| Module pharmacie (029)      |  **~70 %** | Backend fait ; app acheteur P01–P14 faite (alerte, réponses, déblocage, retrait ou livreur ivia, paiement) ; app pharmacie, app livreur et écrans du back-office faits |
| Connexion v2 (001, ADR 0012) | **~95 %** | Tout est codé (changement de numéro compris) ; reste la mise en service WhatsApp (+228 99 30 99 45, voir docs/whatsapp-mise-en-service.md) et le fournisseur SMS |
| Démarches hors code         |  **~10 %** | Société, agrégateur de paiement, Play Store, Meta, domaine                 |

---

## 1. Backend — fait

Go 1.27, PostgreSQL 18 + PostGIS, tâches de fond River, 29 migrations, documentation interactive
(Swagger) sur `/docs`, contrat OpenAPI vérifié par les tests.

**Comptes et connexion**
- **Connexion v2 par numéro (ADR 0012, spec 001)** — nouveau :
  - code à 6 chiffres par **WhatsApp**, **SMS en secours** ; valable 5 min, usage unique ;
  - aucun compte créé avant la saisie du nom (inscription en attente de 15 min) ;
  - limites : 1 code par minute, 10 par jour et par numéro, 10 par appareil et par heure, plafond global horaire avec alerte admin ;
  - **5 codes faux bloquent le numéro 15 min** ;
  - jeton d'accès de 15 min et **jeton de rafraîchissement changé à chaque usage** (vol détecté si l'ancien revient) ;
  - **appareils connectés**, déconnexion à distance, alerte « nouvelle connexion » ;
  - le back-office est prévenu de chaque nouvel acheteur ;
  - changement de numéro par code.
- **Admins** : double vérification par **application d'authentification** (Google Authenticator…), 10 codes de secours, réinitialisation par un autre admin (journalisée) ; le code par e-mail reste tant que l'application n'est pas activée.
- Création de compte par code reçu par e-mail puis mot de passe ; connexion par mot de passe (Argon2id, verrou après 10 échecs) ; mot de passe oublié ; connexion avec Google (prête, à activer avec les identifiants) ; double vérification par code pour les admins (ADR 0011).
- Envoi des e-mails : Brevo (staging/production), SMTP vers Mailpit (local, boîte de test sur http://localhost:8025), journaux (tests). E-mail du code aux couleurs de la marque.
- Sessions révocables, rôles acheteur / marchand / livreur / admin, consentement à la politique de confidentialité, suppression du compte.
- Profil, carnet d'adresses avec point GPS, appareils pour les notifications push.

**Boutiques et catalogue**
- Création de boutique par le marchand, catégories de boutique, quartiers, horaires, position GPS.
- Validation par l'admin : publier, refuser (motif), suspendre, rétablir — une boutique non publiée est invisible.
- **Validation du marchand sur pièces** : le marchand dépose sa pièce d'identité (obligatoire) et son registre du commerce (facultatif) dans le stockage privé ; l'admin ne peut publier aucune de ses boutiques sans la pièce d'identité. Pièces effacées à la suppression du compte.
- Produits, photos (envoi direct vers le stockage par lien signé), catégories de produits.
- Stock suivi ou non suivi, réservation du stock à la commande, rendu à l'annulation.
- Recherche : texte, catégorie, prix, quartier, « autour de moi » (distance).

**Commande et paiement**
- Panier mono-boutique (raisons d'une ligne bloquée en texte et en code, stock restant), commande en retrait ou en livraison, frais de livraison calculés (forfait + km, coefficient de distance).
- Machine à états de la commande avec historique horodaté (append-only).
- Paiement Mobile Money (Flooz, T-Money) derrière une interface : faux prestataire en local avec webhooks signés (HMAC), revérification automatique, détection des doublons, expiration.
- Marchand : accepter / refuser sous 15 min (sinon annulation et remboursement automatiques), préparation, remise par code à l'acheteur (5 essais, déblocage par l'admin).
- Annulation par l'acheteur, file de remboursement, remboursements.

**Livraison**
- Inscription du livreur, documents (pièce d'identité, permis) dans un stockage privé.
- **Activation obligatoire par l'admin** : impossible de valider sans les deux documents ; le livreur ne travaille qu'une fois validé.
- Disponibilité et position, attribution automatique au livreur le plus proche avec véhicule compatible, proposition de 45 s, alertes si personne n'accepte.
- Déroulé de mission : récupération, remise par code, échec de livraison et retour en boutique confirmé par l'admin.

**Admin et finances**
- Paramètres de la plateforme (commission, barème, délais), journal des actions admin non modifiable.
- Indicateurs : commandes payées par jour, volume, commission, taux d'annulation, délais, attribution en moins de 10 min.
- Relevés marchands (reversements) et marquage « réglé », export des livraisons par livreur.
- Notifications push (Firebase), suivi des erreurs (Sentry).

**Promotion et publicité (IVI et AWU-IVI d'abord)** — nouveau
- Produits : prix promotionnel avec dates de début et de fin, badges (Promotion, Offre spéciale, Produit vedette, Meilleure vente), rang de mise en avant, caractéristiques. Le prix promo s'applique automatiquement au panier, à la commande et à la recherche ; les produits mis en avant passent en tête des listes.
- Visuels publicitaires publiés par l'admin (bannière, fenêtre, interstitiel, bienvenue, visuel du mois, affiche) : emplacements, apps visées, priorité, poids, période, bouton « Commander » vers un produit, lien vers le site officiel.
- Réglages de diffusion : délai avant la première fenêtre, intervalle minimal, plafond par session, rotation pondérée/aléatoire/par priorité, coupure générale.
- Statistiques : affichages, clics, fermetures, clics vers le site officiel, commandes après clic, conversion, ventes payées par produit promu. Événements anonymes (aucune donnée personnelle), limités par adresse IP.

**Alerte médicament (module pharmacie, spec 029)** — mis à jour d'après les maquettes P01 à P14
- Pharmacies : inscription dans l'app pharmacie, pièces (autorisation d'ouverture, inscription à l'Ordre, pièce du titulaire) dans le stockage privé, validation par l'admin qui donne le rôle pharmacien ; ouverte, fermée, de garde ou **24 h/24** ; **planning de garde** saisi par l'admin ; suspension.
- Alerte du client : **liste de produits** (base de médicaments avec autocomplétion, ou saisie libre ; forme, quantité), photos d'ordonnance ou de boîte, « générique accepté », note. Rayon **au choix (2, 5 ou 10 km)** avec le nombre de pharmacies joignables affiché avant l'envoi ; **relance** avec un autre rayon (photos reprises).
- Réponses ligne par ligne (disponible, quantité, prix, ordonnance), fenêtre de 20 minutes, compteurs « contactées, vues, réponses », classement par distance.
- **Déblocage par pharmacie** (100 F chacune, Mobile Money) : identité révélée et produits **mis de côté 1 heure** (réservation « M-n », code à 4 chiffres).
- **Aucune commission sur les produits** : le forfait de déblocage suffit ; la pharmacie reçoit le prix complet.
- **Retrait sur place** (paiement à la pharmacie) ou **livreur ivia** : la recherche du livreur le plus proche démarre dès le choix ; **le client ne paie (produits + livraison) qu'une fois le livreur trouvé**, et le livreur ne récupère la commande qu'après ce paiement. Livraison permise sur ordonnance, avec vérification de l'ordonnance par le livreur à la remise.
- Commande préparée signalée par la pharmacie, suivi (déblocage, paiement, préparation, récupération, remise), distance et temps à pied ou délai de livraison.
- Annulation par la pharmacie : client remboursé, **forfait de déblocage compris** ; annulation après paiement remboursée ; codes limités à 5 essais par quart d'heure.
- Pharmacies de garde à proximité en accès public (accueil) ; base de médicaments gérée dans le back-office.
- Solde dû à chaque pharmacie, reversements enregistrés par l'admin (journalisés, plafonnés au solde) ; indicateurs ; tous les chiffres réglables dans le back-office.
- Données de santé : photos privées, lues par lien de 10 minutes par les seules pharmacies sollicitées, **supprimées 24 heures** après l'alerte ; la pharmacie ne voit jamais l'identité du client (prénom seulement à la réservation).
- 61 routes documentées dans le contrat OpenAPI, tests de bout en bout (livraison complète avec recherche du livreur avant paiement, ordonnance vérifiée à la livraison, retrait, relance, annulation remboursée).

**Jeu de démonstration** (`manage seed-demo`, local uniquement, relançable sans doublon)
- Catalogue haut de gamme : 10 boutiques dans 10 quartiers (concept store, maroquinerie, couture wax de cérémonie, parfums et beauté, pâtisserie fine, épicerie fine, bar à smoothies, high-tech, décoration, sneakers), 52 produits avec 91 vraies photos sous licence libre **embarquées dans le dépôt** (aucune connexion nécessaire, crédits conservés), sous-catégories, promotions et badges. Les boutiques de la première version (marché, épicerie de base…) sont suspendues à la relance.
- Boutique officielle IVI : AWU IVI 1,5 L, 0,5 L, 0,33 L, paquet 30 sachets, bonbonne, avec les photos de la marque, **en vente et en tête de toutes les listes**, promotions (1,5 L à 400 F, paquet à 650 F, bonbonne à 2 500 F). Ce sont des **prix de démonstration** à remplacer par les vrais dans Produits IVI.
- 7 visuels IVI : carrousel d'accueil (toutes les bannières), bannières glissées dans l'accueil, la recherche et chaque boutique, fenêtres, interstitiels plein écran, bienvenue à l'ouverture. Diffusion insistante : première fenêtre après 8 s, puis toutes les 40 s, jusqu'à 10 par session ; un produit IVI toutes les 4 cartes.
- 12 acheteurs avec adresses, 10 livreurs (en ligne, hors ligne, dossier à valider), 27 commandes couvrant tous les statuts, paniers en cours. Mot de passe commun des comptes de démo : `ivia-demo-2026`.

**Secrets** : jamais dans Git (détection gitleaks en CI, historique vérifié sain) ; en production, un fichier par secret (droits 400, lisible par root et le conteneur seulement), jamais en variable d'environnement ; démarrage refusé avec un secret faible ou mal protégé ; aucun secret dans les journaux ; sauvegardes chiffrées.

**Qualité** : tests sur base réelle pour chaque module et parcours de bout en bout ; `go vet`, `gofmt`, `govulncheck` en CI.

## 2. Back-office web (`admin/`) — fait

Next.js 16, TypeScript strict, Tailwind 4, même langage visuel que les apps (logotypes, Berkeley Blue, Imperial Red, cartes arrondies, mosaïque).

- Connexion admin par mot de passe puis second facteur (maquettes B01, B02) : **application d'authentification** (ou code de secours) si elle est activée, sinon code reçu par e-mail ; mot de passe oublié, session en cookie httpOnly limitée à 8 h, accès coupé dès que le rôle admin est retiré.
- **Sécurité** (nouveau) : activation de l'application d'authentification avec QR code généré dans le navigateur, 10 codes de secours (copier, imprimer, régénérer), désactivation, sessions ouvertes avec déconnexion ; sur la page Comptes, « Réinitialiser la 2FA » d'un autre admin (motif, journalisé).
- Tableau de bord (maquette B03), mis à jour en direct toutes les 30 s : 5 tuiles « à traiter », indicateurs avec objectifs et comparaison, graphique livraison/retrait sur 14 jours, livreurs maintenant, paiements, commandes en cours filtrables, journal des actions ; recherche globale, notifications, période au choix.
- Boutiques : filtres par statut, colonne « Pièces », fiche boutique avec les pièces du marchand (lien temporaire), publier / refuser / suspendre / rétablir avec confirmation et motif ; « Publier » n'apparaît qu'une fois la pièce d'identité déposée.
- Livreurs : liste filtrée, dossier complet (documents consultables par lien temporaire, documents manquants signalés), valider et activer / refuser / suspendre / rétablir.
- Commandes : recherche par numéro, filtres, fiche (détail, frise d'historique, produits, paiements), actions : annuler, retirer le livreur, confirmer le retour, débloquer le code, rembourser.
- Remboursements en attente, paramètres de la plateforme, journal des actions en français.
- Paiements : filtres (en attente, doublons, échoués, remboursements), revérification auprès du prestataire, remboursement d'un paiement reçu en double.
- Relevés marchands : aperçu par boutique et période, création, marquage « réglé » avec la référence du virement, suppression d'un relevé ouvert.
- Livraisons par livreur sur une période, avec total et export CSV pour la paie.
- Comptes : recherche, filtre par rôle, droits admin donnés ou retirés (journalisé).
- Référentiels : catégories de produits (avec catégorie parente), catégories de boutique, quartiers ; ajout, modification, désactivation.
- **Publicité** : visuels en cartes (aperçu, statut de diffusion, chiffres), publication avec envoi d'image et aperçu, arrêt/reprise, suppression ; indicateurs et graphique par jour ; tableau des produits promus ; réglages de diffusion.
- **Produits IVI** : liste (mis en avant d'abord, filtre gamme IVI), fiche complète : photos (ajout, retrait), prix, mise en vente, stock, promotion datée, badges, rang, caractéristiques.
- Pages d'erreur, chargement et 404 soignées ; image Docker, job CI.

- **Santé et immobilier** (nouveau) : pharmacies (dossier, pièces, décision, planning de garde, solde et reversements), alertes médicament, paiements santé avec remboursement, base des médicaments, réglages ; annonces immobilières (publier, modifier, retirer, photos), journalisées.

## 3. Apps mobiles (`mobile/`, Flutter) — fait

- Espace de travail à 3 apps (acheteur, marchand, livreur) + client API + bibliothèque d'interface commune.
- Splash et présentation des 3 apps.
- **Connexion acheteur par numéro** (nouveau) : numéro, code reçu sur WhatsApp (ou par SMS, au choix ou en secours), validation automatique au 6e chiffre, « Faisons connaissance » (prénom, nom, consentement) pour un numéro nouveau ; jeton d'accès renouvelé en silence ; Profil › Appareils connectés (déconnecter un appareil ou tous). Marchand, livreur et pharmacie utilisent la même connexion par numéro, avec le badge de leur app. Le back-office reste en e-mail, mot de passe et 2FA.
- **Acheteur** : accueil (zone par position ou quartier, catégories, boutiques, nouveautés), recherche avec filtres et tri, fiches boutique et produit, panier (008), commande en retrait et suivi avec code de remise (009, en relecture).
- **Marchand** : création de la boutique, écran « en cours de validation » avec dépôt de la pièce d'identité et du RCCM, catalogue (produits, photos, brouillons, retrait, stock) (005).
- **Livreur** : dossier de candidature avec documents (018).
- **Accueil A01** (nouveau) : « Livrer à », « Tout ce qu'il vous faut, tout près de vous. », recherche « Pharmacie, plat, taxi… », les 8 services (Pharmacie, Alimentation, E-Bazar actifs ; Restaurant, Taxi, Immobilier, Conciergerie, Coursier « bientôt »), bannières à la une, boutiques près de vous, **pharmacies de garde** avec appel direct.
- **Ivia Business** (nouveau nom de l'app marchand) : workflow complet par espace : secteur (boutique, immobilier, artisan, restaurant), formulaire propre au secteur, justificatifs (identité, selfie, pièces du secteur), compte de versement Mobile Money, code PIN, envoi au back-office, brouillon invisible des clients, décision (valider, compléter, refuser) ; à la connexion : choix de l'espace, accès selon le statut, alerte de nouvel appareil. Back-office : menu « Ivia Business ». Nouvelle identité « poste de pilotage », distincte de l'app client : panneau sombre, barre fixe, une couleur par secteur, animations courtes. Modules agence et artisan : annonces, services, disponibilités. Reste : réservations et demandes de visite (il faut d'abord le parcours côté client) ; écrans commandes et catalogue à restyler en détail ; tests de l'app à réécrire.
- **App marchand, compléments** (nouveau) : Compte refait (identité, boutique, changer de numéro, appareils connectés, aide), écran **Revenus et relevés** (à recevoir, déjà reversé, ventes brutes, détail commande par commande). Démo : Afi sur 90 00 01 01.
- **Workflow d'inscription pharmacie** (nouveau) : fiche avec e-mail, placement sur la carte, autorisation d'exercice, identité, photo de la devanture, planning de garde (créneaux ou import), compte de versement, envoi ; décision du back-office (valider, compléter, refuser) ; la nuit (20 h à 7 h, réglable), seules les gardes reçoivent les alertes ; écran d'autorisations du téléphone. Connexion par numéro uniquement ; e-mail sur la fiche, qui reçoit l'avis de validation (push + e-mail). Reste : sonnerie plein écran (notifications push non branchées).
- **App pharmacie** (`apps/pharmacy`, nouveau, port 8093 en aperçu) : connexion par numéro, inscription de l'officine et dépôt des 3 pièces, attente de validation ; alertes reçues en direct (produits, photos d'ordonnance, note, compte à rebours), réponse produit par produit (disponible, prix, quantité, ordonnance) ou refus ; réservations (commande prête, remise au comptoir par code à 4 chiffres, livreur ivia, annulation remboursée) ; ouverte / de garde / 24 h, planning de garde, appareils connectés ; solde à recevoir et reversements. Démo : titulaires sur 91 80 02 01 à 91 80 02 11.
- **Alerte médicament (P01 à P14)** (nouveau) : médicaments (base avec autocomplétion ou saisie libre, quantités), photos d'ordonnance ou de boîte, générique, rayon 2/5/10 km avec le nombre de pharmacies ; suivi en direct (contactées, vues, réponses), réponses classées par distance avec disponibilités et prix ; déblocage d'une pharmacie (Mobile Money) ; réservation avec code à 4 chiffres et mise de côté ; **retrait sur place** ou **livreur ivia** (adresse, devis, recherche du livreur, paiement une fois le livreur trouvé, suivi, appel) ; relance avec un autre rayon ; annulation.
- **Changer de numéro** (nouveau) : code envoyé au nouveau numéro.
- **Profil complet** (nouveau) : photo de profil, informations personnelles, adresses, notifications (catégories, son, vibration), sécurité (numéro, appareils connectés), aide (contact WhatsApp, FAQ), suppression du compte.
- **Factures PDF** (nouveau) : « Télécharger la facture » sur chaque commande payée et réservation pharmacie réglée.
- **Commande en livraison** (nouveau) : choix de l'adresse et frais affichés avant de payer.
- **Logos Moov Money et Yas** officiels sur les écrans de paiement.
- **Publicité IVI (acheteur)** : carrousel de bannières dans un ordre tiré au hasard qui défile seul ; section « Produits vedettes » ; produits mis en avant glissés dans l'accueil et la navigation du catalogue ; prix promotionnel avec prix normal barré, badges et caractéristiques ; fenêtres et interstitiels plein écran selon les réglages de l'admin (délai, intervalle, plafond par session, rotation), toujours fermables, jamais pendant le panier, la commande ou le paiement ; « Commander maintenant » passe par le panier habituel ; « Visiter le site officiel IVI » ouvre le navigateur ; statistiques anonymes envoyées par lots.

## 4. Infrastructure — fait

- Images Docker de l'API (49 Mo, sans shell, utilisateur non privilégié) et du back-office.
- Production : Docker Compose (PostgreSQL, API, back-office, Caddy avec HTTPS automatique), sauvegardes chiffrées vers Cloudflare R2 et restauration.
- CI GitHub : backend, contrat API, back-office, mobile, images ; Dependabot.
- Local : PostgreSQL (port 5434) et Mailpit via `docker compose`.

---

## Ce qui reste

**Backend**
- [ ] 016 — Brancher le vrai prestataire de paiement (CinetPay, PayDunya, FedaPay ou PayGate) : **bloqué par le choix de l'agrégateur** (ADR 0007).
- [ ] **Mise en service de WhatsApp** : le code est prêt (API Cloud de Meta). Numéro expéditeur vérifié fourni ; il manque :
  - l'identifiant du numéro (`WHATSAPP_PHONE_NUMBER_ID`) ;
  - le jeton système (`WHATSAPP_ACCESS_TOKEN_FILE`) ;
  - un modèle de message « authentification » approuvé par Meta (`WHATSAPP_TEMPLATE`).
- [ ] Choisir le fournisseur SMS (secours de WhatsApp) ; d'ici là, pas de SMS hors local.

**Connexion v2**
- [ ] Marchand : même parcours quand ses maquettes seront fournies.

**Back-office**
- [ ] Tests navigateur (Playwright) des parcours admin.
- [ ] Écrans du module pharmacie : dossiers des pharmacies, planning de garde, base de médicaments, alertes, paiements et remboursements, reversements, réglages (l'API est prête).

**Module pharmacie**
- [ ] App pharmacie (Flutter) : inscription et pièces, ouverture et garde, alertes reçues, réponses, réservations, solde.
- [ ] App livreur : courses pharmacie (attendre le paiement du client, vérification de l'ordonnance).
- [ ] Restaurants, immobilier, taxi, conciergerie et coursier : pas encore de module (tuiles « bientôt » sur l'accueil).

**Publicité IVI**
- [ ] **Remplacer les prix de démonstration des 5 produits IVI** par les vrais prix (back-office, Produits IVI).

**Apps mobiles**
- [ ] Acheteur : écrans de paiement Mobile Money ; commande en livraison ; notifications push.
- [ ] Marchand : commandes reçues (accepter sous 15 min, préparation, remise par code), relevés.
- [ ] Livreur : disponibilité et position, propositions (45 s), déroulé de mission.
- [ ] Profil, adresses, suppression du compte ; publication Play Store.

**Mise en ligne (017)**
- [ ] Louer les VPS (production, staging), DNS, compte Sentry, remplir `infra/.env`, premier déploiement et test de restauration.
- [ ] Domaine d'envoi des e-mails (SPF, DKIM) et clés Brevo : **nécessaire pour recevoir les codes dans une vraie boîte mail**.

**Démarches (porteur du projet)** : RCCM/NIF, contrat avec l'agrégateur, conformité BCEAO, déclaration protection des données, compte Google Play organisation, vérification Meta, liste des quartiers, logos SVG, identifiants des apps, pilotes terrain.

---

## Lancer en local

| Service               | Adresse                       |
| --------------------- | ----------------------------- |
| API                   | http://localhost:8080         |
| Documentation (Swagger) | http://localhost:8080/docs  |
| Back-office           | http://localhost:3000 (compte `admin@ivia.local`) |
| E-mails reçus (Mailpit) | http://localhost:8025       |

**Voir le jeu de démonstration sur un autre poste (ex. chez Jean-Pierre)** — les données ne voyagent pas avec Git, chaque base locale doit être remplie :
1. `git pull` sur `develop` ;
2. PostgreSQL lancé (`POSTGRES_PORT=5434 docker compose up -d`) ;
3. depuis `backend/` : `go run ./cmd/manage seed-demo` (local uniquement ; 2 à 3 minutes ; relançable) ;
4. redémarrer l'API, puis relancer l'app acheteur sur l'émulateur.
