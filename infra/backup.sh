#!/usr/bin/env sh
# Sauvegarde nocturne de la base vers Cloudflare R2 (ADR 0008 : 30 jours conservés).
# Lancée par cron sur le VPS, depuis infra/ :
#   15 2 * * * cd /opt/ivia/infra && ./backup.sh >> /var/log/ivia-backup.log 2>&1
# Prérequis : rclone configuré avec une destination « r2 » (voir README.md) et BACKUP_BUCKET dans .env.
set -eu

cd "$(dirname "$0")"
# shellcheck disable=SC1091
. ./.env
: "${BACKUP_BUCKET:?BACKUP_BUCKET manquant dans .env}"

stamp=$(date -u +%Y-%m-%dT%H%MZ)
file="ivia-${stamp}.sql.gz"

# Format SQL compressé : restaurable avec psql, même sur une version plus récente de PostgreSQL.
docker compose exec -T postgres pg_dump -U ivia -d ivia --no-owner --no-privileges | gzip -9 > "/tmp/${file}"

# Une sauvegarde vide ou tronquée ne doit jamais remplacer les bonnes.
gzip -t "/tmp/${file}"
size=$(wc -c < "/tmp/${file}")
if [ "$size" -lt 1024 ]; then
  echo "$(date -u) sauvegarde trop petite (${size} octets) : abandon" >&2
  rm -f "/tmp/${file}"
  exit 1
fi

rclone copyto "/tmp/${file}" "r2:${BACKUP_BUCKET}/postgres/${file}"
rm -f "/tmp/${file}"

# Conservation : 30 jours.
rclone delete --min-age 30d "r2:${BACKUP_BUCKET}/postgres/"
echo "$(date -u) sauvegarde ${file} (${size} octets) envoyée"
