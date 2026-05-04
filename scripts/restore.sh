#!/usr/bin/env bash
# =============================================================================
# restore.sh
# =============================================================================
# Restore an Odoo DB from a GCS backup.
#
# USAGE:
#   bash scripts/restore.sh <env> <timestamp> <db_name>
#   bash scripts/restore.sh staging 20260503_030000 tshirt_prod
#
# Lists available backups if no args provided.
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && source .env && set +a

BUCKET="${GCS_BACKUP_BUCKET:-tshirt-odoo-prod-backups}"

# --- List mode ---
if [[ $# -lt 3 ]]; then
    echo "Available backups:"
    gcloud storage ls "gs://${BUCKET}/" --recursive | grep manifest.json | sort -r | head -20
    echo ""
    echo "Usage: $0 <env> <timestamp> <db_name>"
    exit 0
fi

ENV="$1"
TIMESTAMP="$2"
DB_NAME="$3"

WORK_DIR="/tmp/restore-${TIMESTAMP}"
mkdir -p "$WORK_DIR"
trap "rm -rf $WORK_DIR" EXIT

echo "===== Restoring ${DB_NAME} from ${ENV}/${TIMESTAMP} ====="

# --- 1. Download ---
echo "→ Downloading backup..."
gcloud storage cp "gs://${BUCKET}/${ENV}/${TIMESTAMP}/${DB_NAME}.dump.gz" "${WORK_DIR}/"
gcloud storage cp "gs://${BUCKET}/${ENV}/${TIMESTAMP}/filestore.tar.gz" "${WORK_DIR}/" 2>/dev/null || true

# --- 2. Confirm ---
echo ""
echo "⚠  This will DROP and RECREATE database '${DB_NAME}' on the LOCAL stack."
read -p "Continue? (yes/N) " confirm
[[ "$confirm" != "yes" ]] && { echo "Aborted."; exit 1; }

# --- 3. Drop & recreate DB ---
COMPOSE="docker compose -f docker/docker-compose.${ENV}.yml"

echo "→ Dropping & recreating $DB_NAME..."
$COMPOSE exec -T db psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
$COMPOSE exec -T db psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$POSTGRES_USER\";"

# --- 4. Restore DB ---
echo "→ Restoring database (this can take a few minutes)..."
gunzip -c "${WORK_DIR}/${DB_NAME}.dump.gz" \
    | $COMPOSE exec -T db pg_restore -U "$POSTGRES_USER" -d "$DB_NAME" --no-owner --role="$POSTGRES_USER"

# --- 5. Restore filestore ---
if [[ -f "${WORK_DIR}/filestore.tar.gz" ]]; then
    echo "→ Restoring filestore..."
    cat "${WORK_DIR}/filestore.tar.gz" \
        | $COMPOSE exec -T odoo tar -xzf - -C /var/lib/odoo
fi

# --- 6. Neutralize (if not production) ---
if [[ "$ENV" != "production" ]]; then
    echo "→ Neutralizing DB (disabling outgoing mail, crons)..."
    $COMPOSE exec -T odoo odoo neutralize --database "$DB_NAME" || true
fi

echo "===== Restore complete ====="
