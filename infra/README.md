# Déploiement (ADR 0008)

Un VPS par environnement (production, staging), Docker Compose, Caddy pour le HTTPS. L'image de
l'API est construite par la CI à chaque fusion sur `main` et publiée sur GitHub Container Registry
(`ghcr.io/<propriétaire>/ivia-api:<sha>`).

## Préparer le serveur (une fois)

1. VPS Ubuntu LTS ; mises à jour de sécurité automatiques (`unattended-upgrades`) ; SSH par clé
   uniquement (`PasswordAuthentication no`) ; pare-feu n'ouvrant que 22, 80 et 443
   (`ufw allow OpenSSH && ufw allow 80,443/tcp && ufw allow 443/udp && ufw enable`).
2. Docker et le plugin Compose ; un utilisateur `deploy` membre du groupe `docker`.
3. `git clone` du dépôt dans `/opt/ivia`, puis dans `infra/` :
   - `cp .env.example .env && chmod 600 .env`, et remplir les valeurs ;
   - `mkdir -p secrets && chmod 700 secrets`, et y déposer `fcm.json` (compte de service Firebase).
4. DNS : `API_DOMAIN` pointe vers l'adresse du VPS (Caddy obtient le certificat tout seul).
5. Si le paquet GHCR est privé : `docker login ghcr.io` avec un jeton en lecture seule des paquets.
6. Sauvegardes : installer `rclone`, `rclone config` avec une destination nommée `r2`
   (type S3, fournisseur Cloudflare, clé R2 limitée au compartiment des sauvegardes), puis la ligne
   cron indiquée en tête de `backup.sh`.

## Déployer une version

```sh
cd /opt/ivia && git pull
cd infra
# API_TAG = SHA du commit fusionné sur main (image publiée par la CI)
sed -i "s/^API_TAG=.*/API_TAG=<sha>/" .env
docker compose pull && docker compose up -d
docker compose logs -f api        # « serveur démarré », version = <sha>
curl -fsS https://$API_DOMAIN/ready
```

Les migrations s'appliquent au démarrage de l'API. Premier admin :
`docker compose run --rm --entrypoint /usr/local/bin/manage api grant-admin <email>`.

## Revenir en arrière

Remettre l'`API_TAG` précédent puis `docker compose up -d`. Les migrations restent compatibles
avec la version précédente du code (on ajoute, puis on supprime dans une version ultérieure).

## Sauvegardes et restauration

- `backup.sh` : `pg_dump` compressé chaque nuit vers R2, contrôlé (archive valide, taille minimale),
  conservé 30 jours. Ajouter aussi l'instantané automatique du VPS chez l'hébergeur.
- **Restauration testée chaque mois sur staging**, dans une base vide :
  `docker compose down -v` (staging uniquement !), `docker compose up -d postgres`, puis
  `./restore.sh <fichier>` et `docker compose up -d`. `restore.sh` refuse une base non vide.
