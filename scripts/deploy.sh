#!/usr/bin/env bash
# =============================================================================
# deploy.sh
# =============================================================================
# Pulls latest code from git and rebuilds the Odoo container.
# Called by GitHub Actions on push, or manually via SSH.
#
# USAGE:
#   bash scripts/deploy.sh <env>
# =============================================================================

set -euo pipefail

ENV="${1:-}"
[[ ! "$ENV" =~ ^(production|staging|dev)$ ]] && { echo "Usage: $0 <env>"; exit 1; }

cd /opt/odoo-tshirt-company

echo "===== Deploying $ENV at $(date) ====="

# --- 1. Pull latest code ---
git fetch --all --prune
case "$ENV" in
    production) BRANCH=main ;;
    staging)    BRANCH=staging ;;
    dev)        BRANCH=dev ;;
esac

git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

# --- 2. Show what changed ---
echo "→ Recent commits:"
git log -5 --oneline

# --- 3. Rebuild & restart ---
COMPOSE_FILE="docker/docker-compose.${ENV}.yml"

echo "→ Building containers..."
docker compose -f "$COMPOSE_FILE" --env-file .env build

echo "→ Restarting stack..."
docker compose -f "$COMPOSE_FILE" --env-file .env up -d

# --- 4. Update modules (only on staging/dev — production needs manual approval) ---
if [[ "$ENV" != "production" ]]; then
    echo "→ Updating custom modules..."
    sleep 10
    docker compose -f "$COMPOSE_FILE" exec -T odoo \
        odoo --stop-after-init -u tshirt_branding -d tshirt_${ENV} || true
fi

# --- 5. Health check ---
echo "→ Waiting for Odoo to be healthy..."
for i in {1..30}; do
    if docker compose -f "$COMPOSE_FILE" exec -T odoo \
        curl -fsS http://localhost:8069/web/login &>/dev/null; then
        echo "✓ Odoo is up"
        break
    fi
    sleep 5
done

# --- 6. Cleanup old images ---
docker image prune -f

echo "===== Deploy complete ====="
