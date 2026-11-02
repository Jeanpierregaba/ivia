#!/usr/bin/env sh
# Crée les fichiers de secrets de la production dans infra/secrets/ (un fichier par secret).
# À lancer en root depuis infra/ sur le serveur : sudo ./init-secrets.sh
#
# - Les secrets internes (base, sessions, webhooks) sont générés au hasard.
# - Les clés des services externes (Brevo, R2, Sentry) sont demandées sans écho à l'écran.
# - Un fichier existant n'est jamais écrasé : relancer le script ne fait que compléter.
# - Dossier 700, fichiers 400, propriétaire = utilisateur du conteneur qui les lit (API 65532,
#   PostgreSQL 70) : personne d'autre sur le serveur ne peut les lire.
# Rotation d'un secret : voir infra/README.md (« Changer un secret »).
set -eu
umask 077

API_UID=65532 # utilisateur nonroot de l'image distroless de l'API
PG_UID=70     # utilisateur postgres de l'image postgis alpine
DIR=./secrets

[ "$(id -u)" -eq 0 ] || { echo "À lancer en root : sudo ./init-secrets.sh" >&2; exit 1; }
command -v openssl >/dev/null || { echo "openssl est requis" >&2; exit 1; }
mkdir -p "$DIR"
chmod 700 "$DIR"

random() { openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-48; }

# save <nom> <uid> : écrit l'entrée standard dans le fichier, puis fixe propriétaire et droits.
save() {
  cat >"$DIR/$1"
  chown "$2:$2" "$DIR/$1"
  chmod 400 "$DIR/$1"
  echo "  créé : $1"
}

generate() { # generate <nom> <uid>
  if [ -e "$DIR/$1" ]; then echo "  existe déjà : $1"; return; fi
  random | save "$1" "$2"
}

ask() { # ask <nom> <libellé> : saisie masquée ; vide = service non configuré pour l'instant
  if [ -e "$DIR/$1" ]; then echo "  existe déjà : $1"; return; fi
  printf "%s (vide pour plus tard) : " "$2"
  stty -echo 2>/dev/null || true
  IFS= read -r value || value=""
  stty echo 2>/dev/null || true
  echo
  printf '%s' "$value" | save "$1" "$API_UID"
  unset value
}

echo "Secrets générés :"
generate postgres_password "$PG_UID"
if [ ! -e "$DIR/database_url" ]; then
  # Même mot de passe que PostgreSQL, sur le réseau Docker interne (aucun port publié).
  printf 'postgres://ivia:%s@postgres:5432/ivia?sslmode=disable' "$(cat "$DIR/postgres_password")" |
    save database_url "$API_UID"
else
  echo "  existe déjà : database_url"
fi
generate auth_secret "$API_UID"
generate payment_webhook_secret "$API_UID"

echo "Clés des services externes :"
ask brevo_api_key "Clé d'API Brevo (envoi des codes)"
ask r2_access_key_id "Identifiant de clé R2"
ask r2_secret_access_key "Clé secrète R2"
ask sentry_dsn "DSN Sentry"

if [ ! -e "$DIR/fcm.json" ]; then
  : | save fcm.json "$API_UID"
  echo "  À compléter : copier le compte de service Firebase dans $DIR/fcm.json (puis chown $API_UID et chmod 400)"
fi

echo "Terminé. Vérifier : ls -l $DIR (attendu : -r-------- pour chaque fichier)."
