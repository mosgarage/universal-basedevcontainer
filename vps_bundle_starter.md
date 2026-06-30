# cccerith-vps-bundle — Starter Bundle (Ubuntu 22.04)

This document contains the core files for your reusable VPS setup. Copy each file into your repo or server, inspect, edit variables, then run the scripts as described.

---

## Files included in this bundle

1. `vps-setup-full.sh` — main bootstrap (Ubuntu 22.04-targeted)
2. `upgrade-22-to-24.sh` — safe helper to upgrade to Ubuntu 24.04
3. `README.md` — quick guide and usage
4. `.env.example` — variables to edit before running
5. `ssh_config_clean` — recommended clean `~/.ssh/config` for your environment

---

### vps-setup-full.sh
```bash
#!/usr/bin/env bash
# vps-setup-full.sh
# Ubuntu 22.04 targeted, reusable VPS bootstrap
# Edit VARIABLES at top before running.
set -euo pipefail
IFS=$'\n\t'

# -------------------------
# VARIABLES (CUSTOMIZE)
# -------------------------
ADMIN_USER="dev"
WEB_USER="mosgarage"
DEV_GROUP="devops"
SSH_PORT=2244
DOMAIN="mosgarage.xyz"
DEV_DOMAIN="dev.mosgarage.xyz"
WWW_DIR="/home/${WEB_USER}/www/${DOMAIN}"
DEV_DIR="/home/${WEB_USER}/dev"
BACKUP_DIR="/home/${WEB_USER}/backups"
MYSQL_ROOT_PASS="Password123."          # <<< CHANGE BEFORE RUNNING
CRON_TIME="0 3 * * *"
TENANT_DOMAIN="igedevteam.onmicrosoft.com"        # <<< Azure AD tenant domain
TEAMS_WEBHOOK_URL=""                              # <<< optional; set to post analytics
USE_TAILSCALE="Y"                                 # set Y to auto-install tailscale
USE_CLOUDFLARE_TUNNEL="N"                         # set Y to install cloudflared (login interactive)
ENABLE_AADLOGIN="N"                               # set Y to attempt AAD login install (interactive)
EMAIL_FOR_LETSENCRYPT="dev@mosgarage.xyz"        # certbot email

log(){ printf "\n[INFO] %s\n" "$*"; }
warn(){ printf "\n[WARN] %s\n" "$*"; }
die(){ printf "\n[ERROR] %s\n" "$*"; exit 1; }

ensure_root(){
  if [ "$EUID" -ne 0 ]; then
    die "Run as root: sudo bash $0"
  fi
}

apt_install(){
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      apt-get install -y "$pkg"
    fi
  done
}

# START
ensure_root
export DEBIAN_FRONTEND=noninteractive

log "1) Update system"
apt-get update -y
apt-get upgrade -y

log "2) Core packages"
apt_install curl wget git ufw unzip zip apt-transport-https ca-certificates lsb-release software-properties-common
apt_install apache2 mariadb-server mariadb-client php php-mysql php-curl php-xml php-gd php-mbstring libapache2-mod-php certbot python3-certbot-apache php-cli

# Docker (optional runtime)
if ! command -v docker >/dev/null 2>&1; then
  log "Installing docker"
  apt-get install -y docker.io docker-compose
  systemctl enable --now docker
fi

log "3) Create users & groups"
groupadd -f "${DEV_GROUP}"
if ! id -u "${WEB_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${WEB_USER}"
fi
usermod -aG "${DEV_GROUP}" "${WEB_USER}"

if ! id -u "${ADMIN_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${ADMIN_USER}"
fi
usermod -aG sudo "${ADMIN_USER}" || true

log "4) SSH hardening & custom port"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)
# ensure directives present
sed -i "s/^#Port .*$/Port ${SSH_PORT}/" /etc/ssh/sshd_config || true
grep -q "^Port ${SSH_PORT}" /etc/ssh/sshd_config || echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config
grep -q "^PermitRootLogin no" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config
grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
systemctl restart sshd

log "5) Firewall"
ufw allow "${SSH_PORT}/tcp"
ufw allow 'Apache Full'
ufw --force enable

log "6) MariaDB secure-ish setup (minimal)"
# set root password noninteractive (works on fresh installs)
debconf-set-selections <<< "mariadb-server mysql-server/root_password password ${MYSQL_ROOT_PASS}"
debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password ${MYSQL_ROOT_PASS}"
# Run mysql_secure_installation steps minimally
mysql -u root <<MYSQL_CMDS || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
MYSQL_CMDS

log "7) WordPress files & Apache vhost"
mkdir -p "${WWW_DIR}"
chown -R "${WEB_USER}:${WEB_USER}" "${WWW_DIR}"
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar xzf latest.tar.gz
rsync -a wordpress/ "${WWW_DIR}/"
chown -R "${WEB_USER}:${WEB_USER}" "${WWW_DIR}"

cat > /etc/apache2/sites-available/${DOMAIN}.conf <<EOF
<VirtualHost *:80>
  ServerName ${DOMAIN}
  ServerAlias www.${DOMAIN}
  DocumentRoot ${WWW_DIR}
  <Directory ${WWW_DIR}>
    AllowOverride All
    Require all granted
  </Directory>
  ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
  CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined
</VirtualHost>
EOF

a2ensite "${DOMAIN}.conf"
a2enmod rewrite
systemctl reload apache2

log "8) Create WP DB & user"
WP_DB="wp_${WEB_USER//[^a-z0-9]/}_db"
WP_DB_USER="${WEB_USER}_dbuser"
WP_DB_PASS="$(openssl rand -base64 18)"
mysql -u root -p"${MYSQL_ROOT_PASS}" <<MYSQL_CMDS
CREATE DATABASE IF NOT EXISTS ${WP_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'localhost' IDENTIFIED BY '${WP_DB_PASS}';
GRANT ALL PRIVILEGES ON ${WP_DB}.* TO '${WP_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_CMDS

if [ ! -f "${WWW_DIR}/wp-config.php" ]; then
  cp "${WWW_DIR}/wp-config-sample.php" "${WWW_DIR}/wp-config.php"
  sed -i "s/database_name_here/${WP_DB}/" "${WWW_DIR}/wp-config.php"
  sed -i "s/username_here/${WP_DB_USER}/" "${WWW_DIR}/wp-config.php"
  sed -i "s/password_here/${WP_DB_PASS}/" "${WWW_DIR}/wp-config.php"
  chown "${WEB_USER}:${WEB_USER}" "${WWW_DIR}/wp-config.php"
fi

log "9) Install code-server (systemd user service)"
curl -fsSL https://code-server.dev/install.sh | sh
cat > /etc/systemd/system/code-server@${WEB_USER}.service <<'EOF'
[Unit]
Description=code-server for %i
After=network.target

[Service]
User=%i
Environment=HOME=/home/%i
ExecStart=/usr/bin/code-server --bind-addr 127.0.0.1:8080 --auth password
Restart=on-failure

[Install]
WantedBy=default.target
EOF
systemctl daemon-reload
systemctl enable --now code-server@${WEB_USER}
mkdir -p /home/${WEB_USER}/.config/code-server
chown -R ${WEB_USER}:${WEB_USER} /home/${WEB_USER}/.config

log "10) Optional: Tailscale"
if [[ "${USE_TAILSCALE^^}" == "Y" ]]; then
  curl -fsSL https://tailscale.com/install.sh | bash
  sudo -u ${WEB_USER} tailscale up || true
  log "Tailscale installed - authenticate in browser."
fi

log "11) Optional: Cloudflared (manual auth)"
if [[ "${USE_CLOUDFLARE_TUNNEL^^}" == "Y" ]]; then
  curl -fsSL https://pkg.cloudflare.com/gpg | gpg --dearmor | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare.list
  apt-get update -y
  apt-get install -y cloudflared
  log "Run 'cloudflared tunnel login' interactively to finish."
fi

log "12) Backup script + cron"
mkdir -p "${BACKUP_DIR}"
chown -R "${WEB_USER}:${WEB_USER}" "${BACKUP_DIR}"

cat > /usr/local/bin/backup_site.sh <<'EOF'
#!/usr/bin/env bash
set -e
DATE=$(date +"%F-%H%M")
BACKUP_BASE="${BACKUP_DIR}"
mkdir -p "${BACKUP_BASE}/${DATE}"
tar -czf "${BACKUP_BASE}/${DATE}/www.tar.gz" -C "${WWW_DIR}" .
mysqldump -u root -p"${MYSQL_ROOT_PASS}" "${WP_DB}" > "${BACKUP_BASE}/${DATE}/db.sql"
find "${BACKUP_BASE}" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +
EOF
chmod +x /usr/local/bin/backup_site.sh
( crontab -l 2>/dev/null | grep -F "/usr/local/bin/backup_site.sh" ) || ( crontab -l 2>/dev/null; echo "${CRON_TIME} /usr/local/bin/backup_site.sh >> /var/log/backup_site.log 2>&1" ) | crontab -

log "13) SSL (Certbot) - attempt automatic"
if command -v certbot >/dev/null 2>&1; then
  certbot --apache -n --agree-tos --email "${EMAIL_FOR_LETSENCRYPT}" -d "${DOMAIN}" -d "www.${DOMAIN}" || warn "Certbot failed or needs manual DNS confirmation."
fi

log "14) Azure AD login (interactive placeholder)"
if [[ "${ENABLE_AADLOGIN^^}" == "Y" ]]; then
  log "Attempting Azure AD login install (interactive). Follow Microsoft docs if this step fails."
  curl -fsSL https://aka.ms/aadloginlinux > /tmp/aadlogin_install.sh || true
  if [[ -f /tmp/aadlogin_install.sh ]]; then
    bash /tmp/aadlogin_install.sh || warn "AAD login install failed; follow MS docs."
  else
    warn "AAD installer not available; follow official docs."
  fi
fi

log "15) System cleanup & optimization"
apt-get autoremove -y
apt-get autoclean -y
sed -i 's/#SystemMaxUse=/SystemMaxUse=200M/' /etc/systemd/journald.conf || true
systemctl restart systemd-journald || true
echo "fs.inotify.max_user_watches=524288" > /etc/sysctl.d/99-inotify.conf
sysctl -p /etc/sysctl.d/99-inotify.conf || true
systemctl enable --now fstrim.timer || true

log "16) Analytics->Teams helper (installed if TEAMS_WEBHOOK_URL set)"
if [[ -n "${TEAMS_WEBHOOK_URL}" ]]; then
  cat > /usr/local/bin/wp_analytics_to_teams.py <<'PY'
#!/usr/bin/env python3
import os, subprocess, json, datetime, requests
TEAMS_WEBHOOK = os.getenv("TEAMS_WEBHOOK", "${TEAMS_WEBHOOK_URL}")
WWW_DIR = "${WWW_DIR}"
DOMAIN = "${DOMAIN}"
def get_basic():
    stat={'posts':0,'users':0}
    try:
        out = subprocess.check_output(["wp","post","list","--path="+WWW_DIR,"--format=json"], stderr=subprocess.DEVNULL)
        stat['posts']=len(json.loads(out.decode())) if out else 0
    except Exception:
        pass
    try:
        out = subprocess.check_output(["wp","user","list","--path="+WWW_DIR,"--format=json"], stderr=subprocess.DEVNULL)
        stat['users']=len(json.loads(out.decode())) if out else 0
    except Exception:
        pass
    return stat
def post(payload):
    if not TEAMS_WEBHOOK:
        print("No webhook configured.")
        return
    headers={"Content-Type":"application/json"}
    requests.post(TEAMS_WEBHOOK, json=payload, headers=headers, timeout=15)
if __name__=="__main__":
    st=get_basic()
    payload={"title":f"Site metrics for {DOMAIN}","text":f"Date: {datetime.datetime.utcnow().isoformat()}Z\nPosts: {st['posts']}\nUsers: {st['users']}"}
    post(payload)
PY
  chmod +x /usr/local/bin/wp_analytics_to_teams.py
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install --upgrade requests || true
  fi
  ( crontab -l 2>/dev/null | grep -F "wp_analytics_to_teams.py" ) || ( crontab -l 2>/dev/null; echo "30 4 * * * /usr/bin/python3 /usr/local/bin/wp_analytics_to_teams.py >> /var/log/wp_analytics.log 2>&1" ) | crontab -
fi

log "17) Final info"
cat <<INFO

Bootstrap finished (basic). Manual tasks:
 - Edit /home/${WEB_USER}/.config/code-server/config.yaml to set code-server password or use reverse proxy auth.
 - If using Cloudflare Tunnel: run 'cloudflared tunnel login' and create DNS routes for ${DEV_DOMAIN} -> 127.0.0.1:8080
 - If using Azure AD login: follow Microsoft docs to finalize realm join & group mapping.
 - Confirm DB credentials in wp-config.php if you customized things.

Site: http://${DOMAIN}
Dev server: http://127.0.0.1:8080 (proxied via tunnel/NGINX/Caddy recommended)
SSH port: ${SSH_PORT}

WP DB name: ${WP_DB}
WP DB user: ${WP_DB_USER}
WP DB password: stored in MySQL (randomized)
Backups: ${BACKUP_DIR}

INFO
```

---

### upgrade-22-to-24.sh
```bash
#!/usr/bin/env bash
# upgrade-22-to-24.sh
# Safe helper to upgrade Ubuntu 22.04 -> 24.04 (interactive)
set -euo pipefail
IFS=$'\n\t'

log(){ printf "\n[INFO] %s\n" "$*"; }
warn(){ printf "\n[WARN] %s\n" "$*"; }

. /etc/os-release
if [[ "$VERSION_ID" != "22.04" ]]; then
  warn "Script intended for Ubuntu 22.04 -> 24.04. Detected $VERSION_ID. Abort."
  exit 1
fi

log "Updating system"
sudo apt update -y
sudo apt upgrade -y
sudo apt autoremove -y
sudo apt autoclean -y

log "Check disk free space (root)"
df -h /

log "List non-official apt sources (may block upgrade)"
ls /etc/apt/sources.list.d || true

read -rp "Confirm you have backups & snapshots (type YES to continue): " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Abort: take backups/snapshots then rerun."
  exit 1
fi

sudo apt install -y update-manager-core
sudo sed -i 's/^Prompt=.*$/Prompt=lts/' /etc/update-manager/release-upgrades || true

log "Starting release upgrade (interactive)... follow prompts."
sudo do-release-upgrade
log "If process completed, reboot the server: sudo reboot"
```

---

### README.md
```markdown
# Starter Bundle — cccerithparish.org VPS

This repo contains the starter scripts to bootstrap an Ubuntu 22.04 VPS for:
- WordPress (Apache + MariaDB + PHP)
- code-server (dev environment)
- SSH hardening (custom port)
- Backups & analytics → Teams hook
- Optional: Tailscale, Cloudflare Tunnel, Azure AD login

## Quick steps (safe)
1. Edit `vps-setup-full.sh` top VARIABLES: DB root password, DOMAIN, DEV_DOMAIN, TENANT_DOMAIN, TEAMS_WEBHOOK_URL.
2. Upload to your VPS (Ubuntu 22.04).
3. Inspect the script carefully.
4. Run:
   ```bash
   sudo bash vps-setup-full.sh
   ```
5. After run:
   - Finish WordPress setup in the browser: `http://<DOMAIN>/wp-admin`
   - Set code-server password at `/home/cccerith/.config/code-server/config.yaml`
   - If using Cloudflare: run `cloudflared tunnel login` and create routes
   - If enabling Azure AD login: set `ENABLE_AADLOGIN=Y` and follow MS interactive steps

## Upgrade helper
- The file `upgrade-22-to-24.sh` helps safely upgrade to Ubuntu 24.04 (run after backups & snapshot).

## Backups
- Daily backups are installed (script: `/usr/local/bin/backup_site.sh`) and rotated to 7 days.
- To add cloud sync, configure `rclone` and update the backup script.

## Analytics → Teams
- Optional script `wp_analytics_to_teams.py` posts simple site stats to a Teams webhook.
- Extend it to call GA4 / Bing / Clarity APIs and attach CSV/JSON files to Teams or SharePoint.

## Security notes
- Change all placeholder passwords before running.
- Use Contabo snapshot feature before full installs or upgrades.
- Use Tailscale or Cloudflare Tunnel to avoid exposing ports directly.

## Reuse
- Change the VARIABLES block in `vps-setup-full.sh` to reuse for other projects.
- Keep this repo private or store secrets in a vault (do NOT commit passwords).
```

---

### .env.example
```bash
# .env.example
# Copy to .env and edit values before running scripts

ADMIN_USER=ubuntu
WEB_USER=cccerith
SSH_PORT=2244

DOMAIN=cccerithparish.org
DEV_DOMAIN=dev.cccerithparish.org

MYSQL_ROOT_PASS=ChangeMeStrongPass!
TEAMS_WEBHOOK_URL=https://outlook.office.com/webhook/your-webhook-url
TENANT_DOMAIN=yourtenant.onmicrosoft.com

USE_TAILSCALE=N
USE_CLOUDFLARE_TUNNEL=N
ENABLE_AADLOGIN=N

EMAIL_FOR_LETSENCRYPT=admin@example.com
```

---

### Recommended clean ~/.ssh/config (`ssh_config_clean`)
```text
# Clean SSH config for your environment (save as ~/.ssh/config)

Host *
  ServerAliveInterval 60
  ServerAliveCountMax 3
  ForwardAgent no
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m

# Contabo VPS (production + dev)
Host cccerithparish.org dev.cccerithparish.org contabo-cccerith
  HostName 161.97.132.183
  User cccerith
  Port 2244
  IdentityFile ~/.ssh/cccerith_ed25519
  IdentitiesOnly yes
  ForwardAgent yes

# Tailscale hosts (if used) - do not conflict with real hostnames
Host tailscale-*
  ProxyCommand /usr/bin/true

# GitHub (explicit)
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
```

---

## What I packaged here
- Core starter scripts and a clean SSH config template.
- All scripts are intentionally clear and editable. Replace the placeholder secrets before execution.

## Next steps I will do if you say "yes":
1. Produce a downloadable ZIP archive of this bundle (so you can download directly).
2. Generate the Power Automate flow export (to pull GA4/Bing/Clarity into Teams/SharePoint).
3. Produce GA4 + Bing + basic Clarity example scripts and a SharePoint upload script (Graph API).
4. Produce a cleaned `~/.ssh/config` replacement command you can run safely (I will backup your existing file first).

Say **"zip it"** to get the downloadable archive, or **"more analytics"** to have the GA4/Bing/Clarity scripts next.

