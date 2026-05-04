#!/usr/bin/env bash
# =============================================================================
# backup.sh
# =============================================================================
# Daily backup of Odoo PostgreSQL DB + filestore → GCS.
# Runs from cron on production VM.
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")/.."

# --- Load env ---
[[ -f .env ]] && set -a && source .env && set +a

ENV="${ENV:-production}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
BACKUP_DIR="/tmp/odoo-backup-${TIMESTAMP}"
BUCKET="${GCS_BACKUP_BUCKET:-tshirt-odoo-prod-backups}"

mkdir -p "$BACKUP_DIR"
trap "rm -rf $BACKUP_DIR" EXIT

echo "===== Backup started: $TIMESTAMP ====="

# --- 1. Get list of databases ---
DBS=$(docker compose -f docker/docker-compose.${ENV}.yml exec -T db \
    psql -U "$POSTGRES_USER" -tAc \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

# --- 2. Dump each DB ---
for DB in $DBS; do
    echo "→ Dumping $DB..."
    docker compose -f docker/docker-compose.${ENV}.yml exec -T db \
        pg_dump -U "$POSTGRES_USER" -Fc "$DB" \
        | gzip > "${BACKUP_DIR}/${DB}.dump.gz"
done

# --- 3. Backup filestore ---
echo "→ Archiving filestore..."
docker compose -f docker/docker-compose.${ENV}.yml exec -T odoo \
    tar -czf - -C /var/lib/odoo filestore 2>/dev/null \
    > "${BACKUP_DIR}/filestore.tar.gz" || echo "  (no filestore yet)"

# --- 4. Manifest ---
cat > "${BACKUP_DIR}/manifest.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "hostname": "$HOSTNAME",
  "env": "$ENV",
  "databases": [$(echo "$DBS" | sed 's/^/"/;s/$/"/' | paste -sd,)],
  "odoo_version": "18.0"
}
EOF

# --- 5. Upload to GCS ---
echo "→ Uploading to gs://${BUCKET}/${ENV}/${TIMESTAMP}/..."
gcloud storage cp -r "${BACKUP_DIR}/*" "gs://${BUCKET}/${ENV}/${TIMESTAMP}/"

# --- 6. Report ---
SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
echo "===== Backup complete ($SIZE) ====="
echo "Location: gs://${BUCKET}/${ENV}/${TIMESTAMP}/"
