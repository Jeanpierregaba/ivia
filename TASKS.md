# TASKS

<!--
Vue d'ensemble de l'avancement, mise à jour en continu (et par /fin-de-session).
Une ligne par fonctionnalité, avec un lien vers sa spec ; le découpage fin en tâches est dans
docs/specs/NNN-nom/tasks.md. Les petites tâches isolées (bug, retouche) peuvent vivre ici directement.
-->

## En cours

- [ ] **ADR 0011 — connexion par mot de passe** (2026-11-03) : backend fait (création de compte par code puis mot de passe, connexion, verrou après 10 échecs, mot de passe oublié, changement de mot de passe, Google, double vérification des admins, migration 00024, tests). Back-office fait (maquettes B01, B02, B03 : mot de passe puis code, tableau de bord dynamique). Apps mobiles : passées à la connexion par numéro (ADR 0012), la 029 (e-mail, mot de passe, Google) en est retirée (2026-11-06). Reste : suppression côté serveur des routes de connexion par e-mail et par Google des apps (Gedeon) une fois les apps publiées
- [ ] 018 — Espace livreur : lancement, connexion, dossier de candidature ([spec](docs/specs/018-espace-livreur/spec.md)) : relu et corrigé ; appareil photo à vérifier sur un vrai téléphone
- [ ] 004 — Espace marchand : lancement, connexion, création de la boutique ([spec](docs/specs/004-espace-marchand/spec.md)) : relu et corrigé ; reste les clés Google Maps (vérification de la carte)
- [ ] 027 — Splash et présentation des 3 apps ([spec](docs/specs/027-splash-onboarding/spec.md)) : reste la vérification sur Android, la validation des textes et des couleurs par le designer

Fin du squelette (étapes 8-9 du cadrage) :
- [x] Mobile (frontend) — convertir `mobile/` en pub workspace : `apps/buyer`, `apps/seller`, `apps/driver`, `packages/api_client`, `packages/ui` (ADR 0002) ; mettre à jour les commandes Mobile d'`AGENTS.md` et le job `mobile` de la CI
- [x] Back-office (frontend) — créer `admin/` avec Next.js 16, TypeScript, Tailwind, pnpm (ADR 0003) ; ajouter ses commandes à `AGENTS.md`, un job `admin` à la CI et `prettier` au hook de formatage
- [x] Outillage — gitleaks en CI (job `secrets`, 2026-11-02) ; secrets de production en fichiers (`infra/init-secrets.sh`)

## À faire

Le **backend du MVP est implémenté** (voir « Terminé ») : chaque fonctionnalité ci-dessous n'a plus
que sa partie interface (apps Flutter, back-office), sauf mention « backend ». Contrat de l'API :
`backend/api/openapi.yaml`. Ordre : dépendances d'abord, puis valeur ; les phases 1 et 2 forment la
version « retrait seulement » (voir `docs/PRD.md`).

### Phase 1 — Comptes et catalogue
- [x] 001 — Écrans de connexion par OTP e-mail dans les 3 apps
- [ ] 002 — Profil, carnet d'adresses (choix du point sur la carte), suppression du compte
- [x] 003 — Back-office : connexion admin (cookie httpOnly côté serveur Next.js), journal des actions
- [ ] 004 — Boutiques : création côté marchand en cours (validation / suspension dans le back-office : faite)
- [x] 005 — Catalogue : produits et photos (redimensionnées, sans métadonnées GPS, avant envoi) : écrans marchand faits (voir « Terminé »)
- [ ] 006 — Stock : journal des mouvements et alertes de réapprovisionnement (saisie et ajustement de la quantité faits dans 005)
- [ ] **Backend** : clé d'idempotence à la création d'un produit (et des autres créations rejouables depuis les apps), pour qu'un nouvel essai après une coupure ne crée pas de doublon
- [x] **Backend** (pour Gedeon, fait en 010, relu le 2026-11-03) : `POST /v1/payments/{id}/cancel`, revérification des demandes annulées et « Vérifier maintenant » : conformes (propriétaire vérifié, idempotent, validation tardive appliquée puis doublon à rembourser). Corrigé : la limite de 10 demandes par heure (acheteur, numéro) était gardée en mémoire et repartait à zéro à chaque redémarrage ou déploiement ; elle est désormais comptée dans la table `payments` (migration 00023, index), `Limiter.Cancel` retiré. Reste à revoir avec le vrai prestataire (016) s'il permet d'annuler une demande
- [x] **Backend** (pour Gedeon, vu en 009, fait le 2026-11-03) : `GET /v1/orders?group=active|done` renvoie tout un onglet (mêmes groupes que `OrderStatus.isActive`) ; l'app peut lire ce filtre au lieu de répartir les 50 dernières commandes
- [x] **Backend** (pour Gedeon, vu en 008, fait le 2026-11-02 : `issue_code` et `stock_left`) : ajouter à `CartItem` le stock restant en chiffre (`available_quantity`, `null` si non suivi) ; l'app lit aujourd'hui le nombre dans le texte de `issue` (« Plus que 2 en stock. ») pour proposer « Ajuster à 2 »
- [x] **Backend** (pour Gedeon, vu en 028, fait le 2026-11-03) : fichiers orphelins du compartiment privé : la suppression du compte efface tout le dossier `merchants/<id>/` et `drivers/<id>/` (rattaché ou non, même sans candidature) ; tâche quotidienne `uploads.purge_orphans` qui supprime les fichiers privés non rattachés de plus de 24 h ; `ObjectStore.List` (local et R2, pages suivies)
- [x] **Backend** (pour Gedeon, vu en 011, fait le 2026-11-03) : motif de refus limité à 200 caractères (`validation_failed`) ; `GET /v1/seller/orders?group=new|active|done` (mêmes groupes que `tabOf`) ; `Accept` et `Reject` vérifient `seller_deadline_at` : après le délai, 409 `seller_deadline_passed` et la commande est annulée sur-le-champ (acheteur remboursé) sans attendre `SellerTimeout`. À faire côté app : lire `group` au lieu de répartir les 100 dernières commandes, afficher `seller_deadline_passed`
- [ ] **Backend** (pour Gedeon, vu en 029) : « mot de passe oublié » révèle l'existence d'un compte par sa limite (adresse inconnue : jamais de 429 `otp_rate_limited` ; compte connu : 429 dès la deuxième demande dans la minute) : appliquer la même limite par adresse dans les deux cas ; `POST /v1/me/password` renvoie l'erreur du nouveau mot de passe sur le champ `password` alors que le champ envoyé est `new_password` (l'app lit les deux)
- [ ] **Backend** (pour Gedeon, vu à la relecture de la 011 et en préparant la 013) : `ListForSeller` charge chaque commande une à une (commande, lignes, historique, prénom : ~400 requêtes SQL pour 100 commandes) ; `cannot_cancel` répond « La boutique a déjà accepté… » même pour une commande expirée
- [ ] **Mobile** (suite de 009 et 011) : lire le filtre `group` du serveur (`GET /v1/orders?group=active|done` côté acheteur, `GET /v1/seller/orders?group=new|active|done` côté marchand) au lieu de répartir les 50 / 100 dernières commandes ; afficher le refus `seller_deadline_passed` (aujourd'hui message du serveur et commande relue)
- [ ] **Mobile** (vu en 011) : libellé de l'onglet actif « Commandes » coupé (« Comman… ») dans la barre du bas de l'app marchand ; une nouvelle commande dont le délai expire reste « Délai dépassé » jusqu'à 30 s (relecture suivante)
- [x] **Backend** (pour Gedeon, vu en 007, fait le 2026-11-03) : recherche de produits par début du dernier mot (« pag » trouve « pagne », requête `mot1 & mot2:*` construite côté serveur avec lettres et chiffres seulement) ; `%`, `_` et `\` échappés dans le `LIKE` de `SearchShops`. À faire côté app : le faux serveur `FakeSearch` doit suivre (début de mot)
- [x] 007 — Recherche : texte, catégorie, prix, quartier, « autour de moi » : écrans acheteur faits (voir « Terminé »)

### Phase 2 — Commande et paiement (retrait en boutique)
- [x] 008 — Panier mono-boutique : écrans acheteur faits (voir « Terminé »)
- [x] 009 — Commande en retrait et suivi : écrans acheteur faits (voir « Terminé »)
- [x] 010 — Écrans de paiement (attente de validation sur le téléphone, interrogation du statut) : faits (voir « Terminé »)
- [x] 011 — Marchand : acceptation / refus sous 15 min, préparation, remise par code : écrans marchand faits (voir « Terminé »)
- [ ] 012 — Notifications push (`firebase_messaging`, enregistrement `PUT /v1/me/devices`) et liste ; dont la notification de validation promise par les écrans d'attente (boutique, dossier livreur)
- [x] 013 — Suivi de commande et annulation par l'acheteur : suivi fait (009), annulation faite (voir « Terminé »)
- [x] 014 — Back-office : supervision des paiements (liste filtrée, doublons, revérification, remboursement d'un doublon), commandes, actions admin et file de remboursement (2026-11-02)
- [x] 015 — Back-office : référentiels (catégories de produits et de boutique, quartiers), comptes et droits admin, paramètres (2026-11-02)
- [ ] 016 — **Backend** : intégrer le vrai prestataire de paiement derrière `payments.Provider` (dépend de l'ADR 0007 accepté) ; tester ses webhooks réels en staging
- [ ] 017 — **Infra** : préparation faite (2026-11-03) : `infra/MISE-EN-LIGNE.md` (procédure du jour J), `bootstrap-server.sh` (durcissement du VPS, Docker), `preflight.sh` (vérifications sans afficher les secrets), `deploy.sh` (déploiement avec retour arrière automatique), images publiées aussi depuis `develop` (staging). Reste : louer le VPS, DNS, comptes R2 / Brevo / Firebase / Sentry, suivre la procédure ; production après 016

### Phase 3 — Livraison
- [ ] 018 — Livreurs : inscription et envoi des documents (app livreur) ; validation du dossier dans le back-office : faite
- [ ] 019 — Disponibilité et position du livreur (service de premier plan Android, position toutes les 30 s, propositions interrogées toutes les 10 s)
- [ ] 020 — Commande en livraison : adresse, véhicule compatible, frais (écrans)
- [ ] 021 — Attribution : écran de proposition (45 s) ; alertes dans le back-office
- [ ] 022 — Déroulé de mission : itinéraire (app de cartes), récupération, code, échec et retour

### Phase 4 — Finances et lancement
- [ ] 023 — Relevés marchands : back-office fait (aperçu, création, « réglé » avec référence, suppression d'un relevé ouvert, 2026-11-02) ; reste les relevés dans l'app marchand
- [x] 024 — Back-office : livraisons par livreur sur une période, total, export CSV pour la paie (2026-11-02)
- [x] 025 — Back-office : indicateurs métier (`GET /v1/admin/metrics`), tableau de bord
- [ ] 026 — Publication Play Store des 3 apps (fiches, politique de confidentialité, déclarations de localisation)

### Après le MVP (dès que Meta valide)
- [ ] OTP par WhatsApp, puis SMS en secours (implémenter `auth.OTPSender`, ouvrir le canal) ; vérification des numéros existants

### Démarches hors code (porteur du projet)
À lancer tout de suite : plusieurs ont des délais de plusieurs semaines.
- [ ] Société enregistrée : RCCM et NIF
- [ ] Grilles tarifaires officielles des agrégateurs (CinetPay, PayDunya, FedaPay, PayGate Global), vérifier le transfert par API (payout) ; acter le choix dans l'ADR 0007
- [ ] Faire confirmer la conformité BCEAO de l'encaissement pour le compte des marchands
- [ ] Déclaration auprès de l'autorité togolaise de protection des données ; politique de confidentialité
- [ ] Numéro D-U-N-S et compte développeur Google Play « organisation »
- [ ] Vérification de l'entreprise chez Meta et modèle de message OTP WhatsApp
- [ ] Nom de domaine et adresse d'envoi des e-mails (SPF, DKIM) pour Brevo
- [ ] Liste des quartiers de Lomé (données de départ)
- [ ] Charte : fournir les logos en SVG et l'icône adaptative Android, valider les couleurs « proposé » de `docs/DESIGN.md`, maquettes Figma
- [ ] Identifiants des 3 apps (remplacent `com.example.ivia_buyer`, `_seller`, `_driver`)
- [ ] Boutiques et livreurs pilotes pour les tests terrain

## Terminé
- [x] 029 — Connexion par mot de passe et Google dans les 3 apps ([spec](docs/specs/029-connexion-mot-de-passe/spec.md), 2026-11-04) : connexion e-mail et mot de passe (aide « Créez votre mot de passe » pour les comptes de l'ancienne connexion par code, compte bloqué), création de compte et mot de passe oublié (e-mail, 6 cases, mot de passe), Google (bouton masqué sans identifiants), changement de mot de passe dans chaque app ; écrans communs dans `app_core`, ancienne connexion par code retirée des apps ; FakeAuth testé d'abord (79 tests) ; vérifié sur simulateur contre l'API locale. **Remplacée** par la connexion par numéro (ADR 0012) : code retiré des apps et d'`api_client` le 2026-11-06
- [x] 013 — Annulation par l'acheteur ([spec](docs/specs/013-annulation-acheteur/spec.md), 2026-11-04) : « Annuler la commande » sur le suivi tant que la boutique n'a pas accepté ; feuille avec « Vos produits seront libérés. » ou le montant remboursé ; demande de paiement en attente annulée d'abord ; payée entre-temps : feuille rouverte avec le montant ; refus avec un message selon le vrai statut ; liste à jour même si le suivi est quitté ; `IviaAmountRow` commun (montants sans débordement) ; vérifié sur simulateur contre l'API locale
- [x] 011 — Commandes du marchand ([spec](docs/specs/011-commandes-marchand/spec.md), 2026-11-03) : Accueil (nouvelles à accepter avec le temps restant, en cours) ; onglet Commandes (Nouvelles / En cours / Terminées, comptes à rebours, « Afficher plus ») ; détail (articles, stock non suivi, net « Vous recevez », accepter / refuser avec motif / préparer / prête) ; remise par le code de l'acheteur (essais restants, blocage au 5e) ; nouvelles relues toutes les 30 s app ouverte, pastille de l'onglet ; `IviaCountdown`, pastille d'onglet, libellés et `showMessage` communs ; vérifié sur simulateur contre l'API locale
- [x] 008 suite — Panier de l'acheteur (2026-11-02) : `issue_code` et `stock_left` des lignes lus (`CartItem.issueCode`, `stockLeft`) au lieu d'analyser le texte de `issue`, affiché tel quel ; faux serveur mobile à jour
- [x] 028 — Pièces du marchand ([spec](docs/specs/028-pieces-marchand/spec.md), 2026-11-02) : « Vérifions votre identité » après la création de la boutique (pièce d'identité obligatoire, RCCM facultatif, en photo, URL signée privée puis rattachement, nouvel essai sans doublon) ; étape « Pièce d'identité » et « Ajouter ma pièce d'identité » sur l'écran en attente ; ligne de document partagée avec le livreur (`DocumentPhotoRow` dans `app_core`) ; « 004 bis » demandé par Gedeon
- [x] 010 — Paiement Mobile Money ([spec](docs/specs/010-paiement/spec.md), 2026-11-02) : écran Paiement (montant, Flooz / T-Money, numéro du profil), attente « Validez le paiement sur votre téléphone » (temps restant à l'heure du serveur, relecture toutes les 3 s, succès vers le suivi avec le code, échec et « Réessayer », « Je n'ai rien reçu », « Annuler le paiement »), simulation locale (`IVIA_DEV_PAYMENT`) ; backend : `POST /v1/payments/{id}/cancel`, limites par acheteur et par numéro, revérification des demandes annulées, à faire relire par Gedeon
- [x] 009 — Commande en retrait et suivi ([spec](docs/specs/009-commande-retrait/spec.md), 2026-11-02) : écran Commande (retrait, récapitulatif du serveur, « Payer » idempotent), onglet Commandes (en cours / terminées, « Récemment »), suivi (en-tête par statut, code de remise, frise horodatée, relecture toutes les 20 s)
- [x] 008 — Panier de l'acheteur ([spec](docs/specs/008-panier/spec.md), 2026-11-02) : panier d'une boutique gardé sur le serveur, ajout cumulé depuis la fiche produit, « + » des cartes et de la fiche boutique, « Vider le panier ? » pour une autre boutique, icône à pastille, barre « Voir le panier », écran Panier (quantités, retrait avec « Annuler », lignes en erreur, vidage) ; « Commander » annonce la 009 ; test backend des raisons relu par Gedeon le 2026-11-02 (champs structurés `issue_code` et `stock_left` ajoutés, voir « En cours »)
- [x] 007 — Accueil et recherche de l'acheteur ([spec](docs/specs/007-accueil-recherche-acheteur/spec.md), 2026-11-01) : barre du bas, zone (position approximative ou quartier), accueil, onglet Recherche avec filtres et tri, fiches boutique et produit ; position arrondie dans l'URL ([ADR 0010](docs/decisions/0010-position-arrondie-dans-les-recherches.md))
- [x] 005 — Catalogue marchand ([spec](docs/specs/005-catalogue-marchand/spec.md), 2026-11-01) : barre du bas, catalogue par onglets avec recherche et compteurs serveur, création en deux étapes, aperçu, brouillons, modification, retrait et remise en vente, stock ; migration 00021 (états de publication) relue par Gedeon le 2026-11-02 : conforme
- [x] Back-office `admin/` (2026-11-01) : Next.js 16, TypeScript strict, Tailwind 4, pnpm ;
  connexion admin par code (cookie httpOnly), tableau de bord, boutiques, livreurs (dossier et
  activation), commandes (détail et actions admin), remboursements, paramètres, journal ; types
  générés depuis `openapi.yaml` ; image Docker, CI, Compose de production et Caddy (`admin/README.md`)
- [x] Backend (2026-11-01) : activation des livreurs par l'admin sur dossier complet (pièce
  d'identité et permis obligatoires) ; correction d'un dossier refusé (plantait) ; test du
  parcours complet d'activation
- [x] Backend (2026-10-31) : catégories de boutique complètes (gestion admin, fiche publique,
  filtres de recherche) ; suivi des erreurs Sentry (sans donnée personnelle) ; image Docker de
  l'API, `infra/` (Compose de production, Caddy, sauvegarde et restauration vers R2), publication
  de l'image par la CI sur `main`
- [x] Corrections de la revue du 2026-10-30 : `APP_ENV` obligatoire, code de remise compté avant
  comparaison, confirmation du retour par l'admin, machine à états testée exhaustivement, accès aux
  ressources d'autrui testés sur toutes les routes, paiement incohérent en échec, commandes non
  payées masquées au marchand, adresses de livraison effacées à la suppression du compte, plafonds IP relevés
- [x] Backend du MVP (2026-10-30) : schéma complet (16 migrations), 16 modules (connexion OTP et
  sessions, comptes et adresses, quartiers, boutiques, catalogue, stock, recherche, panier,
  commandes et machine à états, paiements avec faux prestataire, webhooks, remboursements,
  livraison et attribution automatique, notifications push FCM, relevés, indicateurs, paramètres
  et journal admin), 124 routes décrites dans `openapi.yaml`, tests de bout en bout sur PostGIS,
  `cmd/manage` (premier admin, données de démonstration), CI (sqlc, govulncheck, contrat)
- [x] Squelette backend Go, app Flutter, PostgreSQL en local (2026-10-29/30)
- [x] Cadrage : PRD, architecture et ADR, garde-fous, backlog (2026-10-30)
