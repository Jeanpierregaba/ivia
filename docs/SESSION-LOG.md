# SESSION-LOG

<!--
Une entrée par session de travail, la plus récente EN HAUT. Rempli par /fin-de-session.
Objectif : que la session suivante reparte avec le contexte, sans deviner.
Reste bref : les décisions vont dans un ADR (docs/decisions/), on se contente d'y faire un lien.

Format :

### AAAA-MM-JJ — titre court
- Fait :
- Pièges rencontrés :
- Décisions : (liens vers les ADR)
- Prochaine étape :
-->

### 2026-11-02 — Back-office complet
- Fait : écrans paiements, relevés marchands (aperçu, création, réglé, suppression), livraisons par
  livreur et export CSV (Route Handler qui relaie le fichier, jeton côté serveur), comptes et droits
  admin, référentiels (catégories, quartiers) ; barre latérale en trois sections ; composants
  `ServerForm`, `Field`, `fieldClass`, `apiRaw`. Vérifié contre l'API locale avec les données de
  démonstration (pages, CSV).
- Pièges rencontrés : 60 s imposées entre deux demandes de code pour le même e-mail (protection
  anti-abus) : en attendre la fin pour rouvrir une session de test.
- Prochaine étape : tests navigateur (Playwright), 016 paiement réel, 017 VPS.

### 2026-11-02 — Pièces du marchand dans l'app, panier structuré
- Fait : app marchand, encart « Vos pièces » sur l'écran d'attente (pièce d'identité obligatoire,
  RCCM facultatif, envoi immédiat), étape « Pièce d'identité » ; `DocumentRow` déplacée dans
  `ivia_app_core` (livreur et marchand) avec précision et état « Envoi… » ; app acheteur sur
  `issue_code` / `stock_left` ; faux serveurs à jour ; test du livreur « en vérification » corrigé
  (il échouait déjà : écran encore défilé, le geste ne tirait pas pour actualiser) ; statut de la
  ligne de document flexible (débordement à 200 % sur 320 dp).
- Pièges rencontrés : RAM (6 Go) : lancer les tests Flutter fichier par fichier ou par groupe
  (`--name`), sinon la VM Dart s'arrête.

### 2026-11-02 — Secrets protégés
- Fait : secrets lus dans des fichiers en staging/production (`<NOM>_FILE`, Compose `secrets:`,
  `/run/secrets`) au lieu de variables d'environnement ; `infra/init-secrets.sh` (génération,
  saisie masquée, dossier 700, fichiers 400) ; `infra/.env` sans secret ; refus au démarrage des
  secrets faibles, d'exemple ou trop ouverts ; configuration masquée dans `%v`, `%+v`, `%#v` et slog ;
  sauvegardes chiffrées par rclone `crypt` ; job CI gitleaks ; historique analysé : aucune fuite.
- Pièges rencontrés : chemins Docker sous Git Bash (`MSYS_NO_PATHCONV=1`) ; les secrets Compose
  hors Swarm gardent propriétaire et droits de l'hôte (d'où chown 65532 / 70).
- Prochaine étape : écrans back-office restants.

### 2026-11-02 — Validation des marchands sur pièces, relecture des commits de Jean-Pierre
- Fait : relecture des 52 commits de develop (005, 007, 008, 009, 018) ; migration 00021 et test du
  panier conformes, suite backend verte. Nouveau : pièces du marchand (migration 00022
  `merchant_documents`, usage d'envoi `merchant_document`, `GET`/`POST /v1/seller/documents`,
  `merchant_documents` sur la boutique) ; publication refusée sans pièce d'identité
  (`merchant_documents_missing`) ; pièces effacées à la suppression du compte ; test de bout en bout.
  Back-office : fiche boutique (`/shops/[id]`) avec les pièces par lien temporaire, colonne
  « Pièces » dans la liste, « Publier » masqué tant que la pièce manque. Panier : `issue_code` et
  `stock_left` ajoutés pour que l'app acheteur ne lise plus le stock dans une phrase.
- Pièges rencontrés : RAM saturée (6 Go) : l'éditeur de liens Go manque de mémoire avec `-p=2`,
  utiliser `GOFLAGS=-p=1`.
- Décisions : pièces rattachées au marchand (la personne), pas à la boutique : un marchand à
  plusieurs boutiques ne dépose sa pièce qu'une fois.
- Prochaine étape : écran de dépôt des pièces dans l'app marchand (Jean-Pierre) ; écrans
  back-office restants ; 016 paiement, 017 VPS.

### 2026-11-01 — Back-office aux couleurs des apps, e-mails reçus en local
- Fait : back-office refait dans le langage visuel des apps (logotypes, barre Berkeley, mosaïque
  « à traiter », fiches livreur et commande à en-tête bleu, frise d'historique, statuts de paiement
  et actions du journal en français, connexion illustrée). Backend : envoi des codes par SMTP
  (`OTP_SENDER=smtp`) vers Mailpit ajouté à `docker-compose.yml` (http://localhost:8025), e-mail du
  code à la charte ; refusé en production. `project_progression.md` créé à la racine.
- Pièges rencontrés : en local, aucun e-mail ne partait (code seulement dans les journaux) : c'est
  voulu par les règles (pas d'envoi réel depuis le local), d'où Mailpit ; une vraie boîte exige Brevo.
- Prochaine étape : écrans back-office restants (relevés, export CSV, catégories, quartiers,
  paiements), choix du prestataire de paiement (016), VPS (017).

### 2026-11-01 — Activation des livreurs et back-office Next.js
- Fait : backend — validation d'un livreur refusée sans pièce d'identité ni permis ; correctif
  (un dossier refusé ne pouvait pas être soumis de nouveau) ; test du parcours d'activation.
  Back-office `admin/` créé (ADR 0003) : connexion admin par code, cookie httpOnly, pages tableau
  de bord, boutiques, livreurs, commandes, remboursements, paramètres, journal ; vérifié contre
  l'API locale (toutes les pages, redirections sans session et session invalide) ; image Docker
  (utilisateur non privilégié), jobs CI `admin` et `admin-image`, Compose et Caddy de production,
  Dependabot npm, Prettier dans le hook de formatage. Mode d'emploi : `admin/README.md`.
- Pièges rencontrés : projet écrit à la main (pas de `create-next-app` ni de CLI shadcn, téléchargements
  de code refusés) ; Next 16 : `cookies()`, `params` et `searchParams` asynchrones, cookies écrits
  seulement en Server Action ou Route Handler ; un fichier `"use server"` n'exporte que des
  fonctions asynchrones ; Tailwind 4 : `rounded-card` généré par `--radius-card` dans `@theme` ;
  `openapi-typescript` exige TypeScript 5 ; Docker Desktop s'arrête parfois (relancer la base).
- Prochaine étape : écrans back-office restants (relevés, export CSV, catégories, quartiers,
  paiements), tests Playwright ; backend : prestataire de paiement (016), VPS (017).

### 2026-10-31 — Compléments backend : catégories, Sentry, déploiement
- Fait : audit du backend contre ARCHITECTURE et les specs 001, 004, 027 (ajouts backend du
  développeur frontend relus : consentement, catégories de boutique) ; catégories de boutique
  complètes (admin, fiche publique, recherche, migration 00020) ; Sentry (erreurs 500, paniques,
  tâches de fond, sans donnée personnelle) ; Dockerfile (49 Mo, utilisateur non privilégié),
  `infra/` validé (Caddy, Compose, ShellCheck) ; job CI de publication de l'image.
- Pièges rencontrés : `openapi.yaml` désormais modifié à la main par les deux développeurs → plus
  de régénération, éditions ciblées ; `RULES.md` interdit le push direct sur `develop` → pull request
  depuis `gedeon` ; Git Bash réécrit les chemins passés à `docker run` (`MSYS_NO_PATHCONV=1`).
- Prochaine étape : préparation des VPS (017) ; prestataire de paiement (016).

### 2026-10-30 — Corrections de la revue du backend
- Fait : 4 points importants et 4 mineurs de la revue corrigés, chacun couvert par un test ;
  migration 00017 (effacement des adresses de livraison) ; route admin `confirm-return`.
- Pièges rencontrés : le test d'attaque parallèle sur le code de remise ne prouvait pas la faille
  (compteur déjà plafonné) → test de régression déterministe (lecture périmée), vérifié en échec
  sur l'ancien code.
- Prochaine étape : inchangée (front, prestataire de paiement, déploiement).

### 2026-10-30 — Backend complet du MVP
- Fait : environnement Windows installé (Go 1.27, sqlc 1.31) ; schéma complet et 16 modules
  backend ; assemblage `internal/app` ; `cmd/manage` ; contrat OpenAPI (124 routes) vérifié par un
  test ; tests de bout en bout par HTTP sur PostGIS (parcours livraison et retrait, dernier
  article, webhooks, paiement tardif, remboursements, attribution, échec de livraison, droits,
  suppression de compte) ; parcours complet vérifié à la main sur l'API lancée ; CI enrichie.
- Pièges rencontrés : `core.autocrlf=true` sur Windows convertissait en CRLF (gofmt en échec) →
  `.gitattributes` force LF ; mémoire de la machine saturée → compiler avec `GOFLAGS=-p=2` et
  lancer sqlc avec `GOMAXPROCS=1` ; ports 5432/5433 déjà pris → `POSTGRES_PORT=5434` ; sqlc ne
  déduit pas la nullité dans les vues ni sur `IDENTITY` → `coalesce`/`NOT NULL` explicites ;
  River refuse d'insérer une tâche sans worker → les tests assemblent toute l'application ;
  govulncheck : faille de `crypto/x509` en Go 1.27.2 → passage à 1.27.3.
- Décisions : [ADR 0009](decisions/0009-recherche-vues-lecture-seule.md) (recherche par vues en
  lecture seule) ; stock dans `stock_levels` ; remboursements écrits une fois le résultat connu
  (`refund_pending` sur le paiement) ; transitions ajoutées au diagramme (voir ARCHITECTURE).
- Prochaine étape : front (workspace Flutter, back-office Next.js) sur le contrat OpenAPI ;
  choix du prestataire de paiement (016) ; déploiement (017).

### 2026-10-30 — Cadrage du MVP et squelette backend
- Fait : squelette Go + Flutter + PostgreSQL/PostGIS ; cadrage complet (PRD, ARCHITECTURE,
  stress-test, AGENTS, RULES, SECURITY, TESTING, backlog) ; backend restructuré en modules
  (`internal/<module>`, `internal/platform`), migrations goose appliquées au démarrage
  (extensions PostGIS, pg_trgm, unaccent), contrat `backend/api/openapi.yaml` ; dépôt poussé sur GitHub.
- Pièges rencontrés : depuis PostgreSQL 18, le volume Docker se monte sur `/var/lib/postgresql` ;
  `go test -race` prend environ 2 min sur le Mac Intel (compilation de la bibliothèque standard).
- Décisions : [ADR 0001 à 0008](decisions/) — Next.js pour le back-office (0003),
  prestataire de paiement encore à choisir (0007, « Proposé »). `docs/DESIGN.md` laissé vide :
  charte en cours de conception.
- Prochaine étape : répartition — backend au collaborateur (spec 001, connexion OTP), frontend
  au porteur du projet (workspace Flutter des 3 apps, back-office Next.js). Lancer les démarches
  hors code de `TASKS.md`.
