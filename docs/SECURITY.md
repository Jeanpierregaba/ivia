# SECURITY — Sécurité de l'application

Points à vérifier, adaptés à la stack (API Go, PostgreSQL, apps Flutter, back-office Next.js).
`/audit-securite` les passe en revue sur le code réel. Une case n'est cochée que lorsque c'est en
place **et** vérifié.

## Secrets et configuration
- [x] Aucun secret dans le code ni dans l'historique git : job `secrets` (gitleaks, historique
      complet) dans la CI, exceptions limitées aux faux secrets de test (`.gitleaks.toml`).
      Historique vérifié le 2026-11-02 : aucune fuite.
- [x] En staging et production, chaque secret est un fichier (`infra/secrets/`, dossier 700,
      fichiers 400 au nom de l'utilisateur du conteneur) monté dans `/run/secrets` et lu par
      `<NOM>_FILE` : jamais en variable d'environnement (invisible dans `docker inspect`), jamais
      dans `infra/.env`. Création et rotation : `infra/init-secrets.sh`, `infra/README.md`.
- [x] L'API refuse de démarrer hors local avec un secret court, d'exemple ou peu aléatoire, un
      fichier de secret trop ouvert, ou une variable et son fichier définis ensemble ; les messages
      ne recopient jamais la valeur, et la configuration se journalise sans ses secrets (testé).
- [ ] Aucun secret exposé au navigateur : les variables `NEXT_PUBLIC_*` ne contiennent que du public.
- [ ] Aucune clé de service dans les apps mobiles ; la clé Google Maps est restreinte aux
      identifiants des apps et à leur empreinte de signature.
- [ ] Clés différentes entre local, staging et production ; prestataire de paiement en mode test
      hors production.
- [ ] Sauvegardes chiffrées avant l'envoi (rclone `crypt`), fichier temporaire réservé à root ;
      mot de passe de chiffrement dans le gestionnaire de mots de passe de l'équipe.
- [ ] Sur le VPS : `.env` (sans secret) en 600, `secrets/` lisible par root seulement, SSH par clé, pare-feu
      n'ouvrant que 80/443, mises à jour de sécurité automatiques.
- [ ] La base de production n'est joignable que depuis le réseau Docker interne (aucun port public).

## Authentification et accès
- [ ] Le contrôle d'accès est appliqué côté serveur, jamais seulement dans l'interface.
- [ ] Chaque requête vérifie que l'utilisateur a le droit d'accéder à CETTE ressource (pas seulement
      qu'il est connecté) ; une ressource d'autrui renvoie 404.
- [ ] Les rôles `driver` et `admin` ne s'obtiennent que par l'action d'un admin.
- [ ] Boutique ou livreur suspendu : accès coupé dès la requête suivante.
- [ ] OTP : 6 chiffres générés par `crypto/rand`, haché, valable 10 min, 5 essais, usage unique ;
      même réponse que le compte existe ou non (pas d'énumération des comptes).
- [ ] Sessions : jeton aléatoire de 32 octets, haché en base, expiration, révocation à la
      déconnexion et à la suppression du compte.
- [ ] Mobile : jeton dans le stockage sécurisé (Keystore Android / Keychain iOS).
- [ ] Back-office : jeton dans un cookie `HttpOnly` + `Secure` + `SameSite=Lax`, jamais exposé au
      JavaScript du navigateur.
- Sans objet — RLS / security rules : aucun client n'accède à la base, tout passe par l'API.

## Paiement
- [ ] Webhook : signature vérifiée, montant et devise comparés à la commande, traitement
      idempotent (référence du prestataire unique en base), réponse rapide puis traitement en tâche de fond.
- [ ] Aucun statut de paiement accepté depuis une app.
- [ ] Les paiements restés en attente sont revérifiés par l'API du prestataire.
- [ ] Remboursements et règlements : déclenchés uniquement par un admin, tracés dans `admin_audit_log`.

## Entrées et sorties
- [ ] Toutes les entrées sont validées côté serveur (types, longueurs, plages : prix > 0,
      quantité ≥ 1, coordonnées valides, numéro togolais au bon format).
- [ ] Requêtes paramétrées uniquement (sqlc), jamais de concaténation SQL.
- [ ] Pas de HTML non échappé dans le back-office (React échappe par défaut ; aucun
      `dangerouslySetInnerHTML` sur une donnée utilisateur).
- [ ] Uploads : URL signée à durée courte (5 min), type (`image/jpeg`, `image/png`, `image/webp`,
      PDF pour les documents) et taille max (5 Mo) imposés à la signature ; clé de fichier choisie
      par le serveur ; documents des livreurs et pièces des marchands dans un bucket privé, lus par URL
      signée réservée aux admins.
- [ ] Taille maximale du corps des requêtes limitée dans l'API.

## Abus
- [ ] Limitation de débit : demande d'OTP (par destinataire et par IP, plafond IP élevé à cause
      du partage d'IP des opérateurs mobiles), vérification d'OTP, recherche, création de commande.
- [ ] Code de remise : 5 essais, puis blocage et intervention de l'admin.
- [ ] Protection CSRF du back-office : cookie `SameSite=Lax` et vérification de l'origine sur les
      actions qui modifient (Server Actions de Next.js).
- [ ] Les messages d'erreur ne révèlent pas d'information interne (pas de trace, pas de SQL).

## Dépendances
- [ ] Audit des dépendances dans la CI : `govulncheck`, `pnpm audit`, `flutter pub outdated`.
- [ ] Mises à jour de sécurité automatisées (Dependabot : Go, pub, npm, GitHub Actions).
- [ ] Fichiers de lock commités (`go.sum`, `pubspec.lock`, `pnpm-lock.yaml`).

## Fonctionnalités IA
- Sans objet — aucune fonctionnalité IA au MVP.

## Données personnelles
Cadre : loi togolaise n° 2019-014 relative à la protection des données à caractère personnel.
- [ ] Données collectées limitées au nécessaire ; position du livreur collectée uniquement quand il
      est disponible ou en mission.
- [ ] Durées de conservation définies : positions brutes des livreurs 30 jours, codes OTP et
      sessions expirées purgés, documents des livreurs et pièces des marchands conservés pendant la
      collaboration, effacés à la suppression du compte (tout le dossier de l'utilisateur, fichiers
      non rattachés compris) ; fichier privé jamais rattaché supprimé après 24 h (tâche quotidienne).
- [ ] Suppression de compte depuis chaque app : données personnelles anonymisées, données
      financières conservées.
- [ ] Données d'un acheteur visibles par un livreur uniquement pendant sa mission.
- [ ] Déclaration ou autorisation auprès de l'autorité togolaise de protection des données
      vérifiée (hébergement hors du Togo).
- [ ] Politique de confidentialité publiée et liée depuis les fiches Play Store.
