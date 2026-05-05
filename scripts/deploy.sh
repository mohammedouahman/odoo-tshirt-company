#!/usr/bin/env bash
# =============================================================================
# Odoo deploy — runs on the target VM, invoked by GitHub Actions
# =============================================================================
# Usage: sudo bash scripts/deploy.sh <production|staging|dev>
# =============================================================================
set -euo pipefail

ENV=${1:?missing env arg: production|staging|dev}
REPO=/opt/odoo-tshirt-company
cd "$REPO"

case "$ENV" in
  production) BRANCH=main;    COMPOSE=docker/docker-compose.production.yml ;;
  staging)    BRANCH=staging; COMPOSE=docker/docker-compose.staging.yml    ;;
  dev)        BRANCH=dev;     COMPOSE=docker/docker-compose.dev.yml        ;;
  *) echo "unknown env: $ENV"; exit 1 ;;
esac

echo "[$(date -u +%FT%TZ)] fetching origin/$BRANCH ..."
git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"

echo "[$(date -u +%FT%TZ)] building & restarting stack via $COMPOSE ..."
docker compose -f "$COMPOSE" --project-directory . --env-file .env up -d --build

echo "[$(date -u +%FT%TZ)] pruning dangling images ..."
docker image prune -f >/dev/null

echo "[$(date -u +%FT%TZ)] deploy done."
