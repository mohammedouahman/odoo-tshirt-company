#!/usr/bin/env bash
# =============================================================================
# provision-vm.sh
# =============================================================================
# Creates a GCP VM for one environment (production/staging/dev) and runs
# a startup script that installs Docker + clones the repo + boots Odoo.
#
# USAGE:
#   bash scripts/provision-vm.sh production
#   bash scripts/provision-vm.sh staging
#   bash scripts/provision-vm.sh dev
# =============================================================================

set -euo pipefail

ENV="${1:-}"
[[ -z "$ENV" ]] && { echo "Usage: $0 <production|staging|dev>"; exit 1; }
[[ ! "$ENV" =~ ^(production|staging|dev)$ ]] && { echo "Invalid env: $ENV"; exit 1; }

PROJECT_ID="${GCP_PROJECT_ID:-tshirt-odoo-427381}"
ZONE="${GCP_ZONE:-europe-west1-b}"
REPO_URL="${REPO_URL:-https://github.com/mohammedouahman/odoo-tshirt-company.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"

# --- Sizing per environment ---
case "$ENV" in
    production)
        MACHINE_TYPE="e2-standard-2"   # 2 vCPU, 8 GB
        DISK_SIZE="50GB"
        TAGS="odoo-server"
        BRANCH="main"
        ;;
    staging)
        MACHINE_TYPE="e2-medium"       # 1 vCPU, 4 GB
        DISK_SIZE="30GB"
        TAGS="odoo-server"
        BRANCH="staging"
        ;;
    dev)
        MACHINE_TYPE="e2-small"        # 0.5 vCPU, 2 GB
        DISK_SIZE="20GB"
        TAGS="odoo-server,odoo-dev"
        BRANCH="dev"
        ;;
esac

VM_NAME="odoo-${ENV}"

echo "=========================================="
echo "Provisioning $ENV VM"
echo "=========================================="
echo "Name:    $VM_NAME"
echo "Type:    $MACHINE_TYPE"
echo "Disk:    $DISK_SIZE"
echo "Branch:  $BRANCH"
echo "=========================================="

# --- Generate startup script ---
STARTUP_SCRIPT=$(mktemp)
cat > "$STARTUP_SCRIPT" <<STARTUP
#!/bin/bash
set -e
exec > >(tee /var/log/startup.log) 2>&1

echo "===== Odoo VM Bootstrap ($ENV) ====="
echo "Started at: \$(date)"

# --- Wait for network ---
sleep 10

# --- System update ---
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \\
    ca-certificates curl gnupg git ufw fail2ban unattended-upgrades \\
    apache2-utils

# --- Install Docker ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \\
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

. /etc/os-release
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \\
    https://download.docker.com/linux/\${ID} \${VERSION_CODENAME} stable" \\
    > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

# --- Firewall (only HTTP/HTTPS/SSH; SSH via IAP is OS-level) ---
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
if [ "$ENV" = "dev" ]; then
    ufw allow 8069/tcp
    ufw allow 8025/tcp
    ufw allow 5050/tcp
fi
echo "y" | ufw enable

# --- Auto security updates ---
dpkg-reconfigure -f noninteractive unattended-upgrades

# --- Clone repo ---
mkdir -p /opt
cd /opt
if [ ! -d odoo-tshirt-company ]; then
    git clone --branch $BRANCH $REPO_URL odoo-tshirt-company
fi
cd odoo-tshirt-company

# --- Generate .env if missing ---
if [ ! -f .env ]; then
    POSTGRES_PASS=\$(openssl rand -hex 32)
    ADMIN_PASS=\$(openssl rand -hex 32)
    cat > .env <<EOF
POSTGRES_USER=odoo
POSTGRES_PASSWORD=\$POSTGRES_PASS
ODOO_ADMIN_PASSWORD=\$ADMIN_PASS
GCP_PROJECT_ID=$PROJECT_ID
GCS_BACKUP_BUCKET=${PROJECT_ID}-backups
EOF
    chmod 600 .env
    echo "→ Generated .env with random passwords"
fi

# --- Setup MailHog basic auth (staging only) ---
if [ "$ENV" = "staging" ]; then
    htpasswd -bc config/nginx/.htpasswd mailadmin \$(openssl rand -hex 12)
    echo "→ MailHog UI protected at /mail/"
fi

# --- Start the stack ---
COMPOSE_FILE="docker/docker-compose.${ENV}.yml"
docker compose -f \$COMPOSE_FILE --project-directory . --env-file .env up -d --build

# --- Setup daily backup cron (production only) ---
if [ "$ENV" = "production" ]; then
    cat > /etc/cron.d/odoo-backup <<EOF
0 3 * * * root /opt/odoo-tshirt-company/scripts/backup.sh >> /var/log/odoo-backup.log 2>&1
EOF
    echo "→ Daily backup scheduled at 03:00 UTC"
fi

echo "===== Bootstrap complete at \$(date) ====="
echo "External IP: \$(curl -s ifconfig.me)"
echo "Odoo URL:    http://\$(curl -s ifconfig.me).nip.io"
STARTUP

# --- Create the VM ---
echo "[1/2] Creating VM..."
gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --boot-disk-size="$DISK_SIZE" \
    --boot-disk-type=pd-balanced \
    --tags="$TAGS" \
    --scopes=cloud-platform \
    --metadata-from-file=startup-script="$STARTUP_SCRIPT" \
    --labels="env=${ENV},app=odoo"

rm "$STARTUP_SCRIPT"

# --- Get external IP ---
echo "[2/2] Waiting for IP assignment..."
sleep 5
EXT_IP=$(gcloud compute instances describe "$VM_NAME" \
    --zone="$ZONE" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "=========================================="
echo "✓ VM $VM_NAME created"
echo "=========================================="
echo "External IP: $EXT_IP"
echo "URL:         http://${EXT_IP}.nip.io"
echo ""
echo "Bootstrap is running (~5-10 min). Track with:"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE --tunnel-through-iap \\"
echo "    --command='sudo tail -f /var/log/startup.log'"
echo ""
echo "Once done, visit: http://${EXT_IP}.nip.io"
echo "=========================================="
