#!/usr/bin/env sh
# Déploie une version, depuis infra/ sur le serveur (utilisateur deploy) :
#
#   ./deploy.sh <sha>               API et back-office au même commit
#   ./deploy.sh <sha-api> <sha-admin>
#
# Les images ghcr.io/<GHCR_OWNER>/ivia-api:<sha> et ivia-admin:<sha> sont publiées par la CI à
# chaque fusion sur main. Le script note la version en place, déploie, puis vérifie l'API
# (/ready, base et migrations) et le back-office (/login) par leur domaine public. Si la nouvelle
# version ne répond pas en 3 minutes, il remet la précédente tout seul.
# Historique : deploy-history.log (date, versions, résultat).
set -eu
cd "$(dirname "$0")"

api_tag=${1:?usage : ./deploy.sh <sha> [sha-admin]}
admin_tag=${2:-$api_tag}
case "$api_tag$admin_tag" in *[!0-9a-f]*) echo "SHA invalide (hexadécimal attendu)." >&2; exit 1 ;; esac

[ -f .env ] || { echo ".env absent : lancer d'abord ./preflight.sh" >&2; exit 1; }
get() { grep -E "^$1=" .env | head -1 | cut -d= -f2 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]//g'; }
prev_api=$(get API_TAG)
prev_admin=$(get ADMIN_TAG)
api_domain=$(get API_DOMAIN)
admin_domain=$(get ADMIN_DOMAIN)

set_tags() {
  # Fichier réécrit en place : droits (600) et propriétaire conservés.
  sed -i "s/^API_TAG=.*/API_TAG=$1/; s/^ADMIN_TAG=.*/ADMIN_TAG=$2/" .env
}

healthy() {
  i=0
  while [ "$i" -lt 36 ]; do
    if curl -fsS --max-time 5 "https://$api_domain/ready" >/dev/null 2>&1 &&
      curl -fsS --max-time 5 -o /dev/null "https://$admin_domain/login" 2>/dev/null; then
      return 0
    fi
    i=$((i + 1))
    sleep 5
  done
  return 1
}

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a deploy-history.log; }

log "déploiement api=$api_tag admin=$admin_tag (précédent api=$prev_api admin=$prev_admin)"
set_tags "$api_tag" "$admin_tag"
if ! docker compose pull api admin; then
  set_tags "$prev_api" "$prev_admin"
  log "ÉCHEC : images introuvables (CI terminée ? paquet GHCR accessible ?) ; rien n'a changé"
  exit 1
fi
docker compose up -d --remove-orphans

if healthy; then
  log "OK : api=$api_tag admin=$admin_tag en service"
  docker image prune -f >/dev/null
  exit 0
fi

log "ÉCHEC : la nouvelle version ne répond pas ; retour à api=$prev_api admin=$prev_admin"
docker compose logs --tail=50 api admin >&2 || true
set_tags "$prev_api" "$prev_admin"
docker compose up -d
if healthy; then
  log "retour arrière OK"
else
  log "ALERTE : la version précédente ne répond pas non plus ; intervention manuelle"
fi
exit 1
