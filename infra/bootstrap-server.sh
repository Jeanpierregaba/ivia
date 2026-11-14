#!/usr/bin/env sh
# Prépare un VPS Ubuntu 24.04 LTS neuf pour ivia (ADR 0008). À lancer UNE fois, en root, juste
# après la création du serveur (la clé SSH de l'équipe doit déjà être dans /root/.ssh/authorized_keys) :
#
#   scp infra/bootstrap-server.sh root@<ip>:/root/ && ssh root@<ip> sh /root/bootstrap-server.sh
#
# Ce que fait le script (relançable sans danger) :
#   - mises à jour, paquets utiles, mises à jour de sécurité automatiques ;
#   - utilisateur « deploy » (clé SSH de root recopiée, membre du groupe docker) ;
#   - SSH : clé uniquement, root interdit (seulement si deploy a bien une clé) ;
#   - pare-feu : 22, 80, 443 (et 443/udp pour HTTP/3) ; fail2ban sur SSH ;
#   - Docker et le plugin Compose (dépôt officiel), journaux des conteneurs limités ;
#   - fichier d'échange de 2 Go s'il n'y en a pas, journaux système limités à 500 Mo ;
#   - dossier /opt/ivia appartenant à deploy.
# Ensuite : suivre infra/MISE-EN-LIGNE.md (étape 3).
set -eu

[ "$(id -u)" -eq 0 ] || { echo "À lancer en root." >&2; exit 1; }
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || { echo "Prévu pour Ubuntu (trouvé : ${ID:-inconnu})." >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

step() { printf '\n==> %s\n' "$1"; }

step "Mises à jour et paquets"
apt-get update -q
apt-get upgrade -yq
apt-get install -yq ca-certificates curl gnupg git ufw fail2ban unattended-upgrades openssl rclone jq dnsutils

step "Mises à jour de sécurité automatiques"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
# Redémarrage automatique la nuit si une mise à jour du noyau l'exige (les conteneurs repartent seuls).
cat >/etc/apt/apt.conf.d/52ivia-reboot <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";
EOF

step "Utilisateur deploy"
if ! id deploy >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" deploy
fi
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
if [ -s /root/.ssh/authorized_keys ] && [ ! -s /home/deploy/.ssh/authorized_keys ]; then
  install -m 600 -o deploy -g deploy /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
fi

step "SSH : clé uniquement"
mkdir -p /etc/ssh/sshd_config.d
{
  echo "PasswordAuthentication no"
  echo "KbdInteractiveAuthentication no"
  echo "PubkeyAuthentication yes"
  echo "X11Forwarding no"
  echo "MaxAuthTries 3"
  # On ne ferme root que si deploy peut se connecter : jamais de serveur inaccessible.
  if [ -s /home/deploy/.ssh/authorized_keys ]; then echo "PermitRootLogin no"; else echo "PermitRootLogin prohibit-password"; fi
} >/etc/ssh/sshd_config.d/10-ivia.conf
sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd

step "Pare-feu et fail2ban"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable
systemctl enable --now fail2ban

step "Docker (dépôt officiel)"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
# Journaux des conteneurs bornés : un disque plein arrête la base.
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "5" },
  "live-restore": true
}
EOF
systemctl enable docker
systemctl restart docker
usermod -aG docker deploy
# Note : Docker contourne ufw pour les ports publiés ; seul Caddy publie 80 et 443 (docker-compose.yml).

step "Mémoire d'échange et journaux"
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=500M\n' >/etc/systemd/journald.conf.d/ivia.conf
systemctl restart systemd-journald

step "Dossier de l'application"
install -d -m 755 -o deploy -g deploy /opt/ivia

echo
echo "Serveur prêt. Vérifier depuis votre poste, AVANT de fermer cette session :"
echo "  ssh deploy@<ip>        (doit fonctionner)"
echo "  ssh root@<ip>          (doit être refusé)"
echo "Puis suivre infra/MISE-EN-LIGNE.md, étape 3."
