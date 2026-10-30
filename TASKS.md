# TASKS

<!--
Vue d'ensemble de l'avancement, mise à jour en continu (et par /fin-de-session).
Une ligne par fonctionnalité, avec un lien vers sa spec ; le découpage fin en tâches est dans
docs/specs/NNN-nom/tasks.md. Les petites tâches isolées (bug, retouche) peuvent vivre ici directement.
-->

## En cours

Fin du squelette (étapes 8-9 du cadrage), à terminer avant la 001 :
- [x] Mobile (frontend) — convertir `mobile/` en pub workspace : `apps/buyer`, `apps/seller`, `apps/driver`, `packages/api_client`, `packages/ui` (ADR 0002) ; mettre à jour les commandes Mobile d'`AGENTS.md` et le job `mobile` de la CI
- [ ] Back-office (frontend) — créer `admin/` avec Next.js 16, TypeScript, Tailwind, pnpm (ADR 0003) ; ajouter ses commandes à `AGENTS.md` et un job `admin` à la CI
- [ ] Outillage — hook de formatage par extension (`gofmt`, `dart format`, `prettier`), Dependabot (gomod, pub, npm), `govulncheck` et gitleaks en CI, variables dans `.env.example`, section « Démarrer » du `README.md`
- [ ] Backend — `sqlc.yaml` et River à brancher avec la première fonctionnalité qui en a besoin (001)

## À faire

Ordre : dépendances d'abord, puis valeur. Chaque ligne devient une spec (`/spec`) au moment de la
commencer. Les phases 1 et 2 forment la version « retrait seulement », lançable vers le 4e mois
si la livraison prend du retard (voir `docs/PRD.md`).

### Phase 1 — Comptes et catalogue
- [ ] 001 — Connexion par OTP e-mail, sessions et rôles (backend + écrans de connexion dans les 3 apps)
- [ ] 002 — Profil, carnet d'adresses et quartiers de Lomé ; suppression du compte
- [ ] 003 — Back-office : connexion admin, journal des actions admin
- [ ] 004 — Boutiques : création par le marchand, validation / suspension par l'admin
- [ ] 005 — Catalogue : catégories, produits, photos (R2), taille de colis
- [ ] 006 — Stock suivi et non suivi
- [ ] 007 — Recherche : texte, catégorie, prix, quartier, « autour de moi »

### Phase 2 — Commande et paiement (retrait en boutique)
- [ ] 008 — Panier mono-boutique
- [ ] 009 — Commande en retrait : machine à états, historique, réservation du stock
- [ ] 010 — Paiement : interface, faux prestataire, webhook, expiration, paiement tardif
- [ ] 011 — Marchand : acceptation / refus sous 15 min, préparation, remise par code
- [ ] 012 — Notifications push (FCM) et liste des notifications
- [ ] 013 — Suivi de commande et annulation par l'acheteur
- [ ] 014 — Back-office : supervision des commandes et paiements, file de remboursement
- [ ] 015 — Paramètres admin : commission, barème et coefficient de distance, délais, catégories
- [ ] 016 — Intégration du vrai prestataire de paiement (dépend de l'ADR 0007 accepté)
- [ ] 017 — Déploiement : VPS de production et de staging, Caddy, sauvegardes testées, Sentry

### Phase 3 — Livraison
- [ ] 018 — Livreurs : inscription, documents, validation / suspension par l'admin
- [ ] 019 — Disponibilité et position du livreur (service de premier plan Android)
- [ ] 020 — Commande en livraison : adresse, véhicule compatible, frais
- [ ] 021 — Attribution automatique des missions (45 s, livreur suivant, alerte admin)
- [ ] 022 — Déroulé de mission : récupération, livraison par code, échec et retour en boutique

### Phase 4 — Finances et lancement
- [ ] 023 — Relevés marchands et marquage « réglé »
- [ ] 024 — Export des livraisons par livreur et par période
- [ ] 025 — Indicateurs métier dans le back-office
- [ ] 026 — Publication Play Store des 3 apps (fiches, politique de confidentialité, déclarations de localisation)

### Après le MVP (dès que Meta valide)
- [ ] OTP par WhatsApp, puis SMS en secours ; vérification des numéros existants

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
- [x] Squelette backend Go, app Flutter, PostgreSQL en local (2026-10-29/30)
- [x] Cadrage : PRD, architecture et ADR, garde-fous, backlog (2026-10-30)
