# Progression du projet ivia

> Fichier tenu à jour à chaque étape. Dernière mise à jour : **2026-11-01**.
> Détail des tâches : [`TASKS.md`](TASKS.md) · journal des sessions : [`docs/SESSION-LOG.md`](docs/SESSION-LOG.md).

## En un coup d'œil

| Partie                      | Avancement | État                                                                       |
| --------------------------- | :--------: | -------------------------------------------------------------------------- |
| Backend (API Go)            |  **~95 %** | Complet pour le MVP ; manque le vrai prestataire de paiement (016)         |
| Back-office web (Next.js)   |  **~70 %** | Écrans d'exploitation faits ; manquent relevés, export CSV, référentiels   |
| Apps mobiles (Flutter)      |  **~25 %** | Splash/présentation, connexion acheteur et marchand, création de boutique  |
| Infrastructure / mise en ligne | **~60 %** | Images Docker, Compose, Caddy, sauvegardes, CI prêts ; serveurs à louer |
| Démarches hors code         |  **~10 %** | Société, agrégateur de paiement, Play Store, Meta, domaine                 |

---

## 1. Backend — fait

Go 1.27, PostgreSQL 18 + PostGIS, tâches de fond River, 20 migrations, documentation interactive
(Swagger) sur `/docs`, contrat OpenAPI vérifié par les tests.

**Comptes et connexion**
- Connexion sans mot de passe par code à 6 chiffres envoyé par e-mail (10 min de validité, renvoi après 60 s, essais limités, anti-abus par adresse et par IP).
- Envoi des e-mails : Brevo (staging/production), SMTP vers Mailpit (local, boîte de test sur http://localhost:8025), journaux (tests). E-mail du code aux couleurs de la marque.
- Sessions révocables, rôles acheteur / marchand / livreur / admin, consentement à la politique de confidentialité, suppression du compte.
- Profil, carnet d'adresses avec point GPS, appareils pour les notifications push.

**Boutiques et catalogue**
- Création de boutique par le marchand, catégories de boutique, quartiers, horaires, position GPS.
- Validation par l'admin : publier, refuser (motif), suspendre, rétablir — une boutique non publiée est invisible.
- Produits, photos (envoi direct vers le stockage par lien signé), catégories de produits.
- Stock suivi ou non suivi, réservation du stock à la commande, rendu à l'annulation.
- Recherche : texte, catégorie, prix, quartier, « autour de moi » (distance).

**Commande et paiement**
- Panier mono-boutique, commande en retrait ou en livraison, frais de livraison calculés (forfait + km, coefficient de distance).
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

**Qualité** : tests sur base réelle pour chaque module et parcours de bout en bout ; `go vet`, `gofmt`, `govulncheck` en CI.

## 2. Back-office web (`admin/`) — fait

Next.js 16, TypeScript strict, Tailwind 4, même langage visuel que les apps (logotypes, Berkeley Blue, Imperial Red, cartes arrondies, mosaïque).

- Connexion admin par code e-mail, session en cookie httpOnly, accès coupé dès que le rôle admin est retiré.
- Tableau de bord : mosaïque « à traiter » (boutiques et livreurs à valider, remboursements, commandes sans livreur), commandes payées par jour, argent (volume, commission), indicateurs.
- Boutiques : filtres par statut, publier / refuser / suspendre / rétablir avec confirmation et motif.
- Livreurs : liste filtrée, dossier complet (documents consultables par lien temporaire, documents manquants signalés), valider et activer / refuser / suspendre / rétablir.
- Commandes : recherche par numéro, filtres, fiche (détail, frise d'historique, produits, paiements), actions : annuler, retirer le livreur, confirmer le retour, débloquer le code, rembourser.
- Remboursements en attente, paramètres de la plateforme, journal des actions en français.
- Pages d'erreur, chargement et 404 soignées ; image Docker, job CI.

## 3. Apps mobiles (`mobile/`, Flutter) — fait

- Espace de travail à 3 apps (acheteur, marchand, livreur) + client API + bibliothèque d'interface commune.
- Splash et présentation des 3 apps.
- Connexion par code e-mail : acheteur et marchand.
- Marchand : création de la boutique (en cours de relecture).

## 4. Infrastructure — fait

- Images Docker de l'API (49 Mo, sans shell, utilisateur non privilégié) et du back-office.
- Production : Docker Compose (PostgreSQL, API, back-office, Caddy avec HTTPS automatique), sauvegardes chiffrées vers Cloudflare R2 et restauration.
- CI GitHub : backend, contrat API, back-office, mobile, images ; Dependabot.
- Local : PostgreSQL (port 5434) et Mailpit via `docker compose`.

---

## Ce qui reste

**Backend**
- [ ] 016 — Brancher le vrai prestataire de paiement (CinetPay, PayDunya, FedaPay ou PayGate) : **bloqué par le choix de l'agrégateur** (ADR 0007).
- [ ] OTP par WhatsApp puis SMS (après validation Meta).

**Back-office**
- [ ] Relevés marchands et marquage « réglé » (l'API est prête).
- [ ] Export CSV des livraisons par livreur (l'API est prête).
- [ ] Gestion des catégories (produits, boutiques), des quartiers et des comptes admin (l'API est prête).
- [ ] Supervision des paiements (liste, revérification, doublons).
- [ ] Tests navigateur (Playwright).

**Apps mobiles**
- [ ] Connexion livreur ; profil et adresses ; catalogue et photos ; stock ; recherche.
- [ ] Panier, commande, écrans de paiement, suivi, notifications push.
- [ ] App livreur : inscription et documents, disponibilité, propositions, mission.
- [ ] Relevés dans l'app marchand ; publication Play Store.

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
