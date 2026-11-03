# Déploiement (ADR 0008)

> **Première mise en ligne : suivre [`MISE-EN-LIGNE.md`](MISE-EN-LIGNE.md)** (procédure pas à pas,
> scripts `bootstrap-server.sh`, `preflight.sh`, `deploy.sh`). Ce fichier décrit le fonctionnement au quotidien.

Un VPS par environnement (production, staging), Docker Compose, Caddy pour le HTTPS. L'image de
l'API est construite par la CI à chaque fusion sur `main` et publiée sur GitHub Container Registry
(`ghcr.io/<propriétaire>/ivia-api:<sha>`).

## Préparer le serveur (une fois)

1. VPS Ubuntu LTS ; mises à jour de sécurité automatiques (`unattended-upgrades`) ; SSH par clé
   uniquement (`PasswordAuthentication no`) ; pare-feu n'ouvrant que 22, 80 et 443
   (`ufw allow OpenSSH && ufw allow 80,443/tcp && ufw allow 443/udp && ufw enable`).
2. Docker et le plugin Compose ; un utilisateur `deploy` membre du groupe `docker`.
3. `git clone` du dépôt dans `/opt/ivia`, puis dans `infra/` :
   - `cp .env.example .env && chmod 600 .env`, et remplir les réglages (aucun secret dans ce fichier) ;
   - `sudo ./init-secrets.sh` : crée `secrets/` (droits 700) avec un fichier par secret (droits 400,
     propriétaire = utilisateur du conteneur qui le lit). Il génère le mot de passe de la base, le
     secret des sessions et celui des webhooks, puis demande sans écho les clés Brevo, R2 et Sentry ;
   - copier le compte de service Firebase dans `secrets/fcm.json`, puis
     `sudo chown 65532:65532 secrets/fcm.json && sudo chmod 400 secrets/fcm.json`.
4. DNS : `API_DOMAIN` et `ADMIN_DOMAIN` pointent vers l'adresse du VPS (Caddy obtient les certificats tout seul).
5. Si le paquet GHCR est privé : `docker login ghcr.io` avec un jeton en lecture seule des paquets.
6. Sauvegardes **chiffrées** : installer `rclone`, puis `sudo rclone config` (configuration de root,
   droits 600) avec deux destinations : `r2` (type S3, fournisseur Cloudflare, clé R2 limitée au
   compartiment des sauvegardes) et `ivia-backup` (type `crypt`, au-dessus de `r2:<compartiment>`,
   noms de fichiers chiffrés, mot de passe et sel générés par rclone). **Recopier le mot de passe et
   le sel de `ivia-backup` dans le gestionnaire de mots de passe de l'équipe** : sans eux, les
   sauvegardes sont illisibles. Puis la ligne cron (root) indiquée en tête de `backup.sh`.

## Déployer une version

```sh
cd /opt/ivia && git pull
cd infra && ./deploy.sh <sha>     # SHA fusionné sur main (production) ou develop (staging)
```

`deploy.sh` télécharge les images publiées par la CI, démarre, vérifie `/ready` et `/login`, et
remet la version précédente tout seul si la nouvelle ne répond pas (`deploy-history.log`).

Les migrations s'appliquent au démarrage de l'API. Premier admin :
`docker compose run --rm --entrypoint /usr/local/bin/manage api grant-admin <email>`.

## Revenir en arrière

Remettre l'`API_TAG` précédent puis `docker compose up -d`. Les migrations restent compatibles
avec la version précédente du code (on ajoute, puis on supprime dans une version ultérieure).

## Secrets

- Jamais dans Git, jamais dans `infra/.env`, jamais dans une variable d'environnement en production :
  un fichier par secret dans `infra/secrets/`, monté en lecture seule dans `/run/secrets` (invisible
  dans `docker inspect`). L'API lit `<NOM>_FILE` et refuse de démarrer si un fichier est lisible par
  d'autres, si une variable et son fichier sont définis ensemble, ou si un secret est court, recopié
  d'un exemple ou peu aléatoire. Les secrets ne sont jamais journalisés.
- Accès : root uniquement sur le serveur ; copie de secours dans le gestionnaire de mots de passe de
  l'équipe. Production et staging ont des secrets différents.
- **Changer un secret** (fuite supposée, départ d'une personne, ou chaque année) :
  `sudo rm secrets/<nom> && sudo ./init-secrets.sh`, puis `docker compose up -d --force-recreate api`.
  Pour `postgres_password`, changer aussi le mot de passe dans la base avant de redémarrer :
  `docker compose exec postgres psql -U ivia -c "ALTER USER ivia PASSWORD '<nouveau>'"` (le
  nouveau mot de passe vient de `secrets/postgres_password`), puis supprimer et recréer
  `secrets/database_url`. Changer `auth_secret` invalide les codes de connexion en cours, pas les
  sessions. Clés externes (Brevo, R2, Sentry) : créer la nouvelle clé chez le fournisseur, la
  déposer, redémarrer, puis révoquer l'ancienne.

## Sauvegardes et restauration

- `backup.sh` : `pg_dump` compressé chaque nuit, chiffré par rclone (`ivia-backup`) avant d'arriver
  sur R2, contrôlé (archive valide, taille minimale), conservé 30 jours. Ajouter aussi l'instantané automatique du VPS chez l'hébergeur.
- **Restauration testée chaque mois sur staging**, dans une base vide :
  `docker compose down -v` (staging uniquement !), `docker compose up -d postgres`, puis
  `./restore.sh <fichier>` et `docker compose up -d`. `restore.sh` refuse une base non vide.
