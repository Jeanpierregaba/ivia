# Progression du projet ivia

> Fichier tenu à jour à chaque étape. Dernière mise à jour : **2026-11-02**.
> Détail des tâches : [`TASKS.md`](TASKS.md) · journal des sessions : [`docs/SESSION-LOG.md`](docs/SESSION-LOG.md).

## En un coup d'œil

| Partie                      | Avancement | État                                                                       |
| --------------------------- | :--------: | -------------------------------------------------------------------------- |
| Backend (API Go)            |  **~95 %** | Complet pour le MVP ; manque le vrai prestataire de paiement (016)         |
| Back-office web (Next.js)   |  **~95 %** | Tous les écrans du MVP faits ; restent les tests navigateur (Playwright)   |
| Apps mobiles (Flutter)      |  **~50 %** | Acheteur jusqu'à la commande en retrait, catalogue marchand, dossier livreur ; paiement et livraison à faire |
| Infrastructure / mise en ligne | **~60 %** | Images Docker, Compose, Caddy, sauvegardes, CI prêts ; serveurs à louer |
| Démarches hors code         |  **~10 %** | Société, agrégateur de paiement, Play Store, Meta, domaine                 |

---

## 1. Backend — fait

Go 1.27, PostgreSQL 18 + PostGIS, tâches de fond River, 22 migrations, documentation interactive
(Swagger) sur `/docs`, contrat OpenAPI vérifié par les tests.

**Comptes et connexion**
- Connexion sans mot de passe par code à 6 chiffres envoyé par e-mail (10 min de validité, renvoi après 60 s, essais limités, anti-abus par adresse et par IP).
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

**Secrets** : jamais dans Git (détection gitleaks en CI, historique vérifié sain) ; en production, un fichier par secret (droits 400, lisible par root et le conteneur seulement), jamais en variable d'environnement ; démarrage refusé avec un secret faible ou mal protégé ; aucun secret dans les journaux ; sauvegardes chiffrées.

**Qualité** : tests sur base réelle pour chaque module et parcours de bout en bout ; `go vet`, `gofmt`, `govulncheck` en CI.

## 2. Back-office web (`admin/`) — fait

Next.js 16, TypeScript strict, Tailwind 4, même langage visuel que les apps (logotypes, Berkeley Blue, Imperial Red, cartes arrondies, mosaïque).

- Connexion admin par code e-mail, session en cookie httpOnly, accès coupé dès que le rôle admin est retiré.
- Tableau de bord : mosaïque « à traiter » (boutiques et livreurs à valider, remboursements, commandes sans livreur), commandes payées par jour, argent (volume, commission), indicateurs.
- Boutiques : filtres par statut, colonne « Pièces », fiche boutique avec les pièces du marchand (lien temporaire), publier / refuser / suspendre / rétablir avec confirmation et motif ; « Publier » n'apparaît qu'une fois la pièce d'identité déposée.
- Livreurs : liste filtrée, dossier complet (documents consultables par lien temporaire, documents manquants signalés), valider et activer / refuser / suspendre / rétablir.
- Commandes : recherche par numéro, filtres, fiche (détail, frise d'historique, produits, paiements), actions : annuler, retirer le livreur, confirmer le retour, débloquer le code, rembourser.
- Remboursements en attente, paramètres de la plateforme, journal des actions en français.
- Paiements : filtres (en attente, doublons, échoués, remboursements), revérification auprès du prestataire, remboursement d'un paiement reçu en double.
- Relevés marchands : aperçu par boutique et période, création, marquage « réglé » avec la référence du virement, suppression d'un relevé ouvert.
- Livraisons par livreur sur une période, avec total et export CSV pour la paie.
- Comptes : recherche, filtre par rôle, droits admin donnés ou retirés (journalisé).
- Référentiels : catégories de produits (avec catégorie parente), catégories de boutique, quartiers ; ajout, modification, désactivation.
- Pages d'erreur, chargement et 404 soignées ; image Docker, job CI.

## 3. Apps mobiles (`mobile/`, Flutter) — fait

- Espace de travail à 3 apps (acheteur, marchand, livreur) + client API + bibliothèque d'interface commune.
- Splash et présentation des 3 apps ; connexion par code e-mail dans les 3 apps.
- **Acheteur** : accueil (zone par position ou quartier, catégories, boutiques, nouveautés), recherche avec filtres et tri, fiches boutique et produit, panier (008), commande en retrait et suivi avec code de remise (009, en relecture).
- **Marchand** : création de la boutique, écran « en cours de validation » avec dépôt de la pièce d'identité et du RCCM, catalogue (produits, photos, brouillons, retrait, stock) (005).
- **Livreur** : dossier de candidature avec documents (018).

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
- [ ] Tests navigateur (Playwright) des parcours admin.

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
