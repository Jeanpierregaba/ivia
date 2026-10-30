# TASKS

<!--
Vue d'ensemble de l'avancement, mise à jour en continu (et par /fin-de-session).
Une ligne par fonctionnalité, avec un lien vers sa spec ; le découpage fin en tâches est dans
docs/specs/NNN-nom/tasks.md. Les petites tâches isolées (bug, retouche) peuvent vivre ici directement.
-->

## En cours

Fin du squelette (étapes 8-9 du cadrage) :
- [x] Mobile (frontend) — convertir `mobile/` en pub workspace : `apps/buyer`, `apps/seller`, `apps/driver`, `packages/api_client`, `packages/ui` (ADR 0002) ; mettre à jour les commandes Mobile d'`AGENTS.md` et le job `mobile` de la CI
- [ ] Back-office (frontend) — créer `admin/` avec Next.js 16, TypeScript, Tailwind, pnpm (ADR 0003) ; ajouter ses commandes à `AGENTS.md`, un job `admin` à la CI et `prettier` au hook de formatage
- [ ] Outillage — gitleaks en CI ; Dependabot npm avec `admin/`

## À faire

Le **backend du MVP est implémenté** (voir « Terminé ») : chaque fonctionnalité ci-dessous n'a plus
que sa partie interface (apps Flutter, back-office), sauf mention « backend ». Contrat de l'API :
`backend/api/openapi.yaml`. Ordre : dépendances d'abord, puis valeur ; les phases 1 et 2 forment la
version « retrait seulement » (voir `docs/PRD.md`).

### Phase 1 — Comptes et catalogue
- [ ] 001 — Écrans de connexion par OTP e-mail dans les 3 apps (stockage sécurisé du jeton)
- [ ] 002 — Profil, carnet d'adresses (choix du point sur la carte), suppression du compte
- [ ] 003 — Back-office : connexion admin (cookie httpOnly côté serveur Next.js), journal des actions
- [ ] 004 — Boutiques : création par le marchand ; validation / suspension dans le back-office
- [ ] 005 — Catalogue : produits et photos (redimensionnées, sans métadonnées GPS, avant envoi)
- [ ] 006 — Stock suivi et non suivi (écrans marchand)
- [ ] 007 — Recherche : texte, catégorie, prix, quartier, « autour de moi »

### Phase 2 — Commande et paiement (retrait en boutique)
- [ ] 008 — Panier mono-boutique
- [ ] 009 — Commande en retrait et suivi
- [ ] 010 — Écrans de paiement (attente de validation sur le téléphone, interrogation du statut)
- [ ] 011 — Marchand : acceptation / refus sous 15 min, préparation, remise par code
- [ ] 012 — Notifications push (`firebase_messaging`, enregistrement `PUT /v1/me/devices`) et liste
- [ ] 013 — Suivi de commande et annulation par l'acheteur
- [ ] 014 — Back-office : supervision des commandes et paiements, file de remboursement
- [ ] 015 — Back-office : paramètres (commission, barème, délais, catégories, quartiers)
- [ ] 016 — **Backend** : intégrer le vrai prestataire de paiement derrière `payments.Provider` (dépend de l'ADR 0007 accepté) ; tester ses webhooks réels en staging
- [ ] 017 — **Backend / infra** : déploiement (Dockerfile de l'API, `infra/` : Compose de production, Caddy, sauvegardes `pg_dump` vers R2 testées), VPS de production et de staging, intégration Sentry

### Phase 3 — Livraison
- [ ] 018 — Livreurs : inscription et envoi des documents (app livreur), validation dans le back-office
- [ ] 019 — Disponibilité et position du livreur (service de premier plan Android, position toutes les 30 s, propositions interrogées toutes les 10 s)
- [ ] 020 — Commande en livraison : adresse, véhicule compatible, frais (écrans)
- [ ] 021 — Attribution : écran de proposition (45 s) ; alertes dans le back-office
- [ ] 022 — Déroulé de mission : itinéraire (app de cartes), récupération, code, échec et retour

### Phase 4 — Finances et lancement
- [ ] 023 — Back-office : relevés marchands et marquage « réglé » ; relevés dans l'app marchand
- [ ] 024 — Back-office : export des livraisons par livreur (CSV)
- [ ] 025 — Back-office : indicateurs métier (`GET /v1/admin/metrics`)
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
- [x] Backend du MVP (2026-10-30) : schéma complet (16 migrations), 16 modules (connexion OTP et
  sessions, comptes et adresses, quartiers, boutiques, catalogue, stock, recherche, panier,
  commandes et machine à états, paiements avec faux prestataire, webhooks, remboursements,
  livraison et attribution automatique, notifications push FCM, relevés, indicateurs, paramètres
  et journal admin), 124 routes décrites dans `openapi.yaml`, tests de bout en bout sur PostGIS,
  `cmd/manage` (premier admin, données de démonstration), CI (sqlc, govulncheck, contrat)
- [x] Squelette backend Go, app Flutter, PostgreSQL en local (2026-10-29/30)
- [x] Cadrage : PRD, architecture et ADR, garde-fous, backlog (2026-10-30)
