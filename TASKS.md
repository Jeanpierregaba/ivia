# TASKS

<!--
Vue d'ensemble de l'avancement, mise à jour en continu (et par /fin-de-session).
Une ligne par fonctionnalité, avec un lien vers sa spec ; le découpage fin en tâches est dans
docs/specs/NNN-nom/tasks.md. Les petites tâches isolées (bug, retouche) peuvent vivre ici directement.
-->

## En cours

- [ ] 009 — Commande en retrait et suivi ([spec](docs/specs/009-commande-retrait/spec.md)) : plan validé, en cours d'implémentation
- [ ] 018 — Espace livreur : lancement, connexion, dossier de candidature ([spec](docs/specs/018-espace-livreur/spec.md)) : relu et corrigé ; appareil photo à vérifier sur un vrai téléphone
- [ ] 004 — Espace marchand : lancement, connexion, création de la boutique ([spec](docs/specs/004-espace-marchand/spec.md)) : relu et corrigé ; reste les clés Google Maps (vérification de la carte)
- [ ] 027 — Splash et présentation des 3 apps ([spec](docs/specs/027-splash-onboarding/spec.md)) : reste la vérification sur Android, la validation des textes et des couleurs par le designer

Fin du squelette (étapes 8-9 du cadrage) :
- [x] Mobile (frontend) — convertir `mobile/` en pub workspace : `apps/buyer`, `apps/seller`, `apps/driver`, `packages/api_client`, `packages/ui` (ADR 0002) ; mettre à jour les commandes Mobile d'`AGENTS.md` et le job `mobile` de la CI
- [x] Back-office (frontend) — créer `admin/` avec Next.js 16, TypeScript, Tailwind, pnpm (ADR 0003) ; ajouter ses commandes à `AGENTS.md`, un job `admin` à la CI et `prettier` au hook de formatage
- [ ] Outillage — gitleaks en CI

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
- [ ] **Backend** (pour Gedeon, vu en 008) : ajouter à `CartItem` le stock restant en chiffre (`available_quantity`, `null` si non suivi) ; l'app lit aujourd'hui le nombre dans le texte de `issue` (« Plus que 2 en stock. ») pour proposer « Ajuster à 2 »
- [ ] **Backend** (pour Gedeon, vu en 007) : recherche par préfixe du dernier mot (« pag » doit trouver « pagne » : la recherche part pendant la frappe ; aujourd'hui plein texte entier + trigramme) ; échapper `%` et `_` dans le `LIKE` de `SearchShops`
- [x] 007 — Recherche : texte, catégorie, prix, quartier, « autour de moi » : écrans acheteur faits (voir « Terminé »)

### Phase 2 — Commande et paiement (retrait en boutique)
- [x] 008 — Panier mono-boutique : écrans acheteur faits (voir « Terminé »)
- [ ] 009 — Commande en retrait et suivi
- [ ] 010 — Écrans de paiement (attente de validation sur le téléphone, interrogation du statut)
- [ ] 011 — Marchand : acceptation / refus sous 15 min, préparation, remise par code
- [ ] 012 — Notifications push (`firebase_messaging`, enregistrement `PUT /v1/me/devices`) et liste ; dont la notification de validation promise par les écrans d'attente (boutique, dossier livreur)
- [ ] 013 — Suivi de commande et annulation par l'acheteur
- [ ] 014 — Back-office : supervision des paiements (liste, revérification, doublons) ; commandes, actions admin et file de remboursement : faites
- [ ] 015 — Back-office : catégories de produits et de boutique, quartiers, comptes admin ; paramètres (commission, barème, délais) : faits
- [ ] 016 — **Backend** : intégrer le vrai prestataire de paiement derrière `payments.Provider` (dépend de l'ADR 0007 accepté) ; tester ses webhooks réels en staging
- [ ] 017 — **Infra** : louer et préparer les VPS de production et de staging, remplir `infra/.env`, DNS, compte Sentry, puis premier déploiement et premier test de restauration (mode d'emploi : `infra/README.md`). Image, Compose, Caddy, sauvegardes, Sentry et publication CI : faits. Vérifier que Caddy ne journalise pas les paramètres d'URL ([ADR 0010](docs/decisions/0010-position-arrondie-dans-les-recherches.md))

### Phase 3 — Livraison
- [ ] 018 — Livreurs : inscription et envoi des documents (app livreur) ; validation du dossier dans le back-office : faite
- [ ] 019 — Disponibilité et position du livreur (service de premier plan Android, position toutes les 30 s, propositions interrogées toutes les 10 s)
- [ ] 020 — Commande en livraison : adresse, véhicule compatible, frais (écrans)
- [ ] 021 — Attribution : écran de proposition (45 s) ; alertes dans le back-office
- [ ] 022 — Déroulé de mission : itinéraire (app de cartes), récupération, code, échec et retour

### Phase 4 — Finances et lancement
- [ ] 023 — Back-office : relevés marchands et marquage « réglé » ; relevés dans l'app marchand
- [ ] 024 — Back-office : export des livraisons par livreur (CSV)
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
- [x] 008 — Panier de l'acheteur ([spec](docs/specs/008-panier/spec.md), 2026-11-02) : panier d'une boutique gardé sur le serveur, ajout cumulé depuis la fiche produit, « + » des cartes et de la fiche boutique, « Vider le panier ? » pour une autre boutique, icône à pastille, barre « Voir le panier », écran Panier (quantités, retrait avec « Annuler », lignes en erreur, vidage) ; « Commander » annonce la 009 ; test backend des raisons à faire relire par Gedeon
- [x] 007 — Accueil et recherche de l'acheteur ([spec](docs/specs/007-accueil-recherche-acheteur/spec.md), 2026-11-01) : barre du bas, zone (position approximative ou quartier), accueil, onglet Recherche avec filtres et tri, fiches boutique et produit ; position arrondie dans l'URL ([ADR 0010](docs/decisions/0010-position-arrondie-dans-les-recherches.md))
- [x] 005 — Catalogue marchand ([spec](docs/specs/005-catalogue-marchand/spec.md), 2026-11-01) : barre du bas, catalogue par onglets avec recherche et compteurs serveur, création en deux étapes, aperçu, brouillons, modification, retrait et remise en vente, stock ; migration 00021 (états de publication) à faire relire par Gedeon dans la PR
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
