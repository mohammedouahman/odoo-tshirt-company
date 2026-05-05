#!/usr/bin/env bash
# =============================================================================
# Odoo daily backup -> GCS
# =============================================================================
# Runs on each VM as root via cron.
# Reads compose env from /opt/odoo-tshirt-company/.env
# =============================================================================
set -euo pipefail

REPO=/opt/odoo-tshirt-company
ENV_FILE=$REPO/.env
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)

if   docker ps --format '{{.Names}}' | grep -q odoo_db_prod;    then ENV=prod;    DB_C=odoo_db_prod;    APP_C=odoo_app_prod;    DB_NAME=tshirt_prod
elif docker ps --format '{{.Names}}' | grep -q odoo_db_staging; then ENV=staging; DB_C=odoo_db_staging; APP_C=odoo_app_staging; DB_NAME=tshirt_staging
elif docker ps --format '{{.Names}}' | grep -q odoo_db_dev;     then ENV=dev;     DB_C=odoo_db_dev;     APP_C=odoo_app_dev;     DB_NAME=tshirt_dev
else echo "no odoo db container found"; exit 1
fi

set -a; source "$ENV_FILE"; set +a
if [ "$ENV" = dev ]; then POSTGRES_USER=odoo; POSTGRES_PASSWORD=odoo; fi

BUCKET=$(grep '^GCS_BACKUP_BUCKET=' "$ENV_FILE" | cut -d= -f2 || true)
[ -z "${BUCKET:-}" ] && BUCKET=tshirt-odoo-427381-backups

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

DUMP=$WORK/${ENV}_${DB_NAME}_${TS}.sql.gz
FS=$WORK/${ENV}_filestore_${TS}.tar.gz

echo "[$(date -u +%FT%TZ)] dumping $DB_NAME from $DB_C ..."
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$DB_C" \
    pg_dump -U "$POSTGRES_USER" -d "$DB_NAME" --no-owner --no-acl --format=plain \
    | gzip -9 > "$DUMP"

echo "[$(date -u +%FT%TZ)] archiving filestore from $APP_C ..."
docker exec "$APP_C" tar -czf - -C /var/lib/odoo/filestore "$DB_NAME" 2>/dev/null > "$FS" || \
    echo "  (filestore empty or not yet created — skipping)"

echo "[$(date -u +%FT%TZ)] uploading to gs://$BUCKET/$ENV/$TS/ ..."
gsutil -q cp "$DUMP" "gs://$BUCKET/$ENV/$TS/"
[ -s "$FS" ] && gsutil -q cp "$FS" "gs://$BUCKET/$ENV/$TS/"

echo "[$(date -u +%FT%TZ)] done. Files at gs://$BUCKET/$ENV/$TS/"
