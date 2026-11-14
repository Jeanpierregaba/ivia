#!/usr/bin/env sh
# Restauration d'une sauvegarde dans une base VIDE (test mensuel sur staging, ADR 0008).
#   ./restore.sh ivia-2026-10-31T0215Z.sql.gz
# Refuse de s'exécuter si la base contient déjà des données : jamais d'écrasement accidentel.
set -eu
umask 077

cd "$(dirname "$0")"
# shellcheck disable=SC1091
. ./.env
: "${BACKUP_REMOTE:=ivia-backup}"
file="${1:?usage : ./restore.sh <fichier de sauvegarde>}"

tables=$(docker compose exec -T postgres psql -U ivia -d ivia -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders'")
if [ "$tables" != "0" ]; then
  echo "La base contient déjà le schéma ivia : restauration refusée (utiliser une base vide)." >&2
  exit 1
fi

rclone copyto "${BACKUP_REMOTE}:postgres/${file}" "/tmp/${file}"
gzip -dc "/tmp/${file}" | docker compose exec -T postgres psql -U ivia -d ivia -v ON_ERROR_STOP=1 --quiet
rm -f "/tmp/${file}"
echo "Restauration terminée. Vérifier : docker compose exec postgres psql -U ivia -d ivia -c 'SELECT count(*) FROM orders'"
