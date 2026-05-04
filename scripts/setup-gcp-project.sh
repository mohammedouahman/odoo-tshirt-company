#!/usr/bin/env bash
# =============================================================================
# setup-gcp-project.sh
# =============================================================================
# One-time setup of the GCP project: enable APIs, create service account,
# create GCS bucket for backups, set up firewall rules.
#
# PREREQUISITES:
#   - gcloud CLI installed locally (https://cloud.google.com/sdk/docs/install)
#   - Logged in: `gcloud auth login`
#   - Billing account linked to your project
#
# USAGE:
#   bash scripts/setup-gcp-project.sh
# =============================================================================

set -euo pipefail

# --- Configuration ---
PROJECT_ID="${GCP_PROJECT_ID:-tshirt-odoo-prod}"
REGION="${GCP_REGION:-europe-west1}"   # Belgium — close to Morocco
ZONE="${GCP_ZONE:-europe-west1-b}"
BACKUP_BUCKET="${GCS_BACKUP_BUCKET:-${PROJECT_ID}-backups}"
SA_NAME="odoo-deployer"

echo "=========================================="
echo "GCP Setup for Odoo T-Shirt Company"
echo "=========================================="
echo "Project ID:    $PROJECT_ID"
echo "Region:        $REGION"
echo "Backup bucket: $BACKUP_BUCKET"
echo "=========================================="
read -p "Continue? (y/N) " -n 1 -r; echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

# --- 1. Set active project ---
echo "[1/6] Setting active project..."
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# --- 2. Enable required APIs ---
echo "[2/6] Enabling APIs (this takes ~2 min)..."
gcloud services enable \
    compute.googleapis.com \
    storage.googleapis.com \
    iam.googleapis.com \
    secretmanager.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    dns.googleapis.com

# --- 3. Create service account for CI/CD ---
echo "[3/6] Creating service account..."
if ! gcloud iam service-accounts describe "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name="Odoo Deployer (GitHub Actions)"
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant roles
for role in \
    roles/compute.instanceAdmin.v1 \
    roles/storage.admin \
    roles/iap.tunnelResourceAccessor \
    roles/secretmanager.secretAccessor \
    roles/logging.logWriter; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --condition=None \
        --quiet >/dev/null
done

# Generate key for GitHub Actions
mkdir -p secrets
gcloud iam service-accounts keys create "secrets/${SA_NAME}-key.json" \
    --iam-account="$SA_EMAIL"
echo "→ Service account key saved to: secrets/${SA_NAME}-key.json"
echo "  Add this as GitHub secret GCP_SA_KEY (paste the entire file)"

# --- 4. Create GCS bucket for backups ---
echo "[4/6] Creating backup bucket..."
if ! gcloud storage buckets describe "gs://${BACKUP_BUCKET}" &>/dev/null; then
    gcloud storage buckets create "gs://${BACKUP_BUCKET}" \
        --location="$REGION" \
        --uniform-bucket-level-access \
        --enable-autoclass    # auto-tier to cheaper storage classes
fi

# Lifecycle: keep 30 days, then delete
cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      { "action": {"type": "Delete"}, "condition": {"age": 30} }
    ]
  }
}
EOF
gcloud storage buckets update "gs://${BACKUP_BUCKET}" --lifecycle-file=/tmp/lifecycle.json

# --- 5. Firewall rules ---
echo "[5/6] Creating firewall rules..."

# HTTP/HTTPS
if ! gcloud compute firewall-rules describe odoo-http &>/dev/null; then
    gcloud compute firewall-rules create odoo-http \
        --direction=INGRESS --action=ALLOW \
        --rules=tcp:80,tcp:443 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=odoo-server
fi

# SSH (via IAP — more secure than open SSH to internet)
if ! gcloud compute firewall-rules describe allow-iap-ssh &>/dev/null; then
    gcloud compute firewall-rules create allow-iap-ssh \
        --direction=INGRESS --action=ALLOW \
        --rules=tcp:22 \
        --source-ranges=35.235.240.0/20 \
        --target-tags=odoo-server
fi

# Dev only — direct Odoo port 8069 + MailHog 8025 + pgAdmin 5050
if ! gcloud compute firewall-rules describe odoo-dev-ports &>/dev/null; then
    gcloud compute firewall-rules create odoo-dev-ports \
        --direction=INGRESS --action=ALLOW \
        --rules=tcp:8069,tcp:8025,tcp:5050 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=odoo-dev
fi

# --- 6. Done ---
echo ""
echo "=========================================="
echo "✓ GCP setup complete"
echo "=========================================="
echo ""
echo "NEXT STEPS:"
echo "  1. Add 'secrets/${SA_NAME}-key.json' to GitHub Secrets as GCP_SA_KEY"
echo "  2. Add GCP_PROJECT_ID=$PROJECT_ID to GitHub Secrets"
echo "  3. Run: bash scripts/provision-vm.sh production"
echo "  4. Run: bash scripts/provision-vm.sh staging"
echo "  5. Run: bash scripts/provision-vm.sh dev"
echo ""
