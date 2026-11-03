#!/usr/bin/env sh
# Vérifications avant le premier déploiement (et après tout changement de configuration), depuis
# infra/ sur le serveur : ./preflight.sh
# N'affiche jamais la valeur d'un secret : seulement s'il est présent, protégé et non vide.
# Code de sortie 0 si tout est bon, 1 sinon (chaque problème est listé).
set -u
cd "$(dirname "$0")" || exit 1

fails=0
ok() { printf '  ok      %s\n' "$1"; }
ko() { printf '  ÉCHEC   %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf '  attention %s\n' "$1"; }

echo "Fichier .env (réglages sans secret)"
if [ ! -f .env ]; then
  ko ".env absent : cp .env.example .env && chmod 600 .env"
else
  [ "$(stat -c %a .env)" = "600" ] && ok ".env en 600" || ko ".env doit être en 600 (chmod 600 .env)"
  for v in GHCR_OWNER API_TAG ADMIN_TAG API_DOMAIN ADMIN_DOMAIN APP_ENV PUBLIC_BASE_URL OTP_SENDER \
    BREVO_SENDER_EMAIL PAYMENT_PROVIDER PUSH_SENDER STORAGE R2_ACCOUNT_ID R2_PUBLIC_BUCKET \
    R2_PRIVATE_BUCKET R2_PUBLIC_BASE_URL; do
    val=$(grep -E "^$v=" .env | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$val" ] && ok "$v renseignée" || ko "$v vide dans .env"
  done
  if grep -Eq '^(AUTH_SECRET|BREVO_API_KEY|PAYMENT_WEBHOOK_SECRET|R2_ACCESS_KEY_ID|R2_SECRET_ACCESS_KEY|SENTRY_DSN|POSTGRES_PASSWORD|DATABASE_URL)=.+' .env; then
    ko ".env contient un secret : le déplacer dans secrets/ (sudo ./init-secrets.sh)"
  fi
  app_env=$(grep -E '^APP_ENV=' .env | cut -d= -f2 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]//g')
  payment=$(grep -E '^PAYMENT_PROVIDER=' .env | cut -d= -f2 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]//g')
  if [ "$app_env" = "production" ] && [ "$payment" = "fake" ]; then
    ko "PAYMENT_PROVIDER=fake interdit en production (tâche 016)"
  fi
fi

echo "Secrets (infra/secrets/)"
if [ ! -d secrets ]; then
  ko "dossier secrets/ absent : sudo ./init-secrets.sh"
else
  [ "$(stat -c %a secrets)" = "700" ] && ok "secrets/ en 700" || ko "secrets/ doit être en 700"
  for f in postgres_password database_url auth_secret payment_webhook_secret; do
    if [ ! -f "secrets/$f" ]; then ko "secrets/$f absent"
    elif [ ! -s "secrets/$f" ]; then ko "secrets/$f vide"
    else
      perm=$(stat -c %a "secrets/$f")
      case "$perm" in 400 | 600) ok "secrets/$f présent ($perm)" ;; *) ko "secrets/$f en $perm (attendu 400)" ;; esac
    fi
  done
  for f in brevo_api_key r2_access_key_id r2_secret_access_key fcm.json sentry_dsn; do
    if [ ! -f "secrets/$f" ]; then ko "secrets/$f absent (fichier vide accepté si le service n'est pas encore branché)"
    elif [ ! -s "secrets/$f" ]; then warn "secrets/$f vide : service non configuré"
    else ok "secrets/$f présent"
    fi
  done
fi

echo "Serveur"
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && ok "Docker démarré" || ko "Docker indisponible (bootstrap-server.sh)"
docker compose version >/dev/null 2>&1 && ok "plugin Compose" || ko "plugin docker compose absent"
ufw status 2>/dev/null | grep -q "Status: active" && ok "pare-feu actif" || warn "pare-feu inactif ou illisible (lancer en root pour vérifier)"
free_gb=$(df -Pk / | awk 'NR == 2 { print int($4 / 1048576) }')
[ "${free_gb:-0}" -ge 10 ] && ok "disque libre : ${free_gb} Go" || ko "moins de 10 Go libres sur / (${free_gb:-?} Go)"

echo "DNS (les domaines doivent viser ce serveur)"
my_ip=$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
for v in API_DOMAIN ADMIN_DOMAIN; do
  d=$(grep -E "^$v=" .env 2>/dev/null | cut -d= -f2 | sed 's/[[:space:]]*#.*$//; s/[[:space:]]//g')
  [ -n "$d" ] || continue
  ips=$(dig +short A "$d" | tr '\n' ' ')
  if [ -z "$ips" ]; then ko "$d ne résout pas (enregistrement A manquant)"
  elif [ -n "$my_ip" ] && ! echo "$ips" | grep -qw "$my_ip"; then ko "$d → $ips, ce serveur est $my_ip"
  else ok "$d → $ips"
  fi
done

echo "Sauvegardes"
if command -v rclone >/dev/null 2>&1 && rclone listremotes 2>/dev/null | grep -q '^ivia-backup:$'; then
  ok "destination rclone ivia-backup configurée"
else
  ko "destination rclone « ivia-backup » (crypt) absente : voir README.md, sauvegardes (lancer en root)"
fi
crontab -l 2>/dev/null | grep -q backup.sh && ok "sauvegarde nocturne planifiée" || warn "ligne cron de backup.sh absente pour cet utilisateur (elle est dans la crontab de root ?)"

echo
if [ "$fails" -eq 0 ]; then echo "Tout est prêt."; exit 0; fi
echo "$fails problème(s) à corriger avant de déployer."
exit 1
