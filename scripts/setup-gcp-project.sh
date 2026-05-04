#!/usr/bin/env bash
# =============================================================================
# setup-gcp-project.sh  (v2 — auto-creates project, checks billing)
# =============================================================================
# Sets up the GCP project from scratch:
#   - Creates the project if it doesn't exist
#   - Links billing (asks user to pick if multiple)
#   - Enables required APIs
#   - Creates service account + key for GitHub Actions
#   - Creates GCS backup bucket
#   - Sets up firewall rules
# =============================================================================

set -euo pipefail

# --- Configuration ---
PROJECT_ID="${GCP_PROJECT_ID:-tshirt-odoo-427381}"
PROJECT_NAME="${GCP_PROJECT_NAME:-T-Shirt Odoo Production}"
REGION="${GCP_REGION:-europe-west1}"
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

# =============================================================================
# 1. Auth check
# =============================================================================
echo ""
echo "[1/8] Verifying gcloud authentication..."
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
    echo "✗ Not logged in to gcloud. Running 'gcloud auth login'..."
    gcloud auth login
    ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
fi
echo "✓ Authenticated as: $ACTIVE_ACCOUNT"

# Application Default Credentials (for some APIs)
if ! gcloud auth application-default print-access-token &>/dev/null; then
    echo "→ Setting up application default credentials..."
    gcloud auth application-default login
fi

# =============================================================================
# 2. Create or select project
# =============================================================================
echo ""
echo "[2/8] Checking project '$PROJECT_ID'..."
if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo "✓ Project '$PROJECT_ID' already exists"
else
    echo "→ Project does not exist. Creating..."
    if ! gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME" 2>&1; then
        echo ""
        echo "✗ Could not create project '$PROJECT_ID'."
        echo "  Possible reasons:"
        echo "    - Project ID is taken globally (try a more unique ID)"
        echo "    - Your account lacks 'Project Creator' role"
        echo ""
        echo "  Try a unique ID like: tshirt-odoo-$(openssl rand -hex 3)"
        exit 1
    fi
    echo "✓ Project created"
fi

gcloud config set project "$PROJECT_ID" --quiet
gcloud config set compute/region "$REGION" --quiet
gcloud config set compute/zone "$ZONE" --quiet

# =============================================================================
# 3. Link billing
# =============================================================================
echo ""
echo "[3/8] Checking billing..."
BILLING_ENABLED=$(gcloud beta billing projects describe "$PROJECT_ID" \
    --format="value(billingEnabled)" 2>/dev/null || echo "False")

if [[ "$BILLING_ENABLED" != "True" ]]; then
    echo "→ Billing not linked. Available billing accounts:"
    gcloud beta billing accounts list

    echo ""
    read -p "Enter billing account ID (e.g. 0X0X0X-0X0X0X-0X0X0X): " BILLING_ID
    [[ -z "$BILLING_ID" ]] && { echo "✗ No billing account provided"; exit 1; }

    gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ID"
    echo "✓ Billing linked"
else
    echo "✓ Billing already linked"
fi

# =============================================================================
# 4. Enable APIs
# =============================================================================
echo ""
echo "[4/8] Enabling required APIs (this takes ~2 min)..."
gcloud services enable \
    compute.googleapis.com \
    storage.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    iap.googleapis.com \
    secretmanager.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    dns.googleapis.com
echo "✓ APIs enabled"

# =============================================================================
# 5. Service account for CI/CD
# =============================================================================
echo ""
echo "[5/8] Creating service account..."
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name="Odoo Deployer (GitHub Actions)"
fi

for role in \
    roles/compute.instanceAdmin.v1 \
    roles/storage.admin \
    roles/iap.tunnelResourceAccessor \
    roles/secretmanager.secretAccessor \
    roles/logging.logWriter \
    roles/iam.serviceAccountUser; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" \
        --condition=None \
        --quiet >/dev/null
done

mkdir -p secrets
KEY_FILE="secrets/${SA_NAME}-key.json"
if [[ ! -f "$KEY_FILE" ]]; then
    gcloud iam service-accounts keys create "$KEY_FILE" --iam-account="$SA_EMAIL"
    echo "✓ Service account key saved to: $KEY_FILE"
else
    echo "✓ Service account key already exists at: $KEY_FILE"
fi

# =============================================================================
# 6. Backup bucket
# =============================================================================
echo ""
echo "[6/8] Creating backup bucket..."
if ! gcloud storage buckets describe "gs://${BACKUP_BUCKET}" &>/dev/null; then
    gcloud storage buckets create "gs://${BACKUP_BUCKET}" \
        --location="$REGION" \
        --uniform-bucket-level-access
    echo "✓ Bucket created"
else
    echo "✓ Bucket already exists"
fi

# Lifecycle policy: 30-day retention
cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      { "action": {"type": "Delete"}, "condition": {"age": 30} }
    ]
  }
}
EOF
gcloud storage buckets update "gs://${BACKUP_BUCKET}" --lifecycle-file=/tmp/lifecycle.json --quiet
rm /tmp/lifecycle.json

# =============================================================================
# 7. Firewall rules
# =============================================================================
echo ""
echo "[7/8] Creating firewall rules..."

create_fw_if_missing() {
    local name="$1"; shift
    if ! gcloud compute firewall-rules describe "$name" &>/dev/null; then
        gcloud compute firewall-rules create "$name" "$@"
        echo "  ✓ $name"
    else
        echo "  ✓ $name (already exists)"
    fi
}

create_fw_if_missing odoo-http \
    --direction=INGRESS --action=ALLOW \
    --rules=tcp:80,tcp:443 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=odoo-server

create_fw_if_missing allow-iap-ssh \
    --direction=INGRESS --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --target-tags=odoo-server

create_fw_if_missing odoo-dev-ports \
    --direction=INGRESS --action=ALLOW \
    --rules=tcp:8069,tcp:8025,tcp:5050 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=odoo-dev

# =============================================================================
# 8. Done
# =============================================================================
echo ""
echo "=========================================="
echo "✓ GCP setup complete"
echo "=========================================="
echo ""
echo "PROJECT:        $PROJECT_ID"
echo "REGION:         $REGION"
echo "BACKUP BUCKET:  gs://${BACKUP_BUCKET}"
echo "SA KEY FILE:    $KEY_FILE"
echo ""
echo "NEXT STEPS:"
echo ""
echo "  1. Add GitHub secrets at:"
echo "     https://github.com/YOUR_USER/odoo-tshirt-company/settings/secrets/actions"
echo ""
echo "     - GCP_SA_KEY      = (paste the contents of $KEY_FILE)"
echo "     - GCP_PROJECT_ID  = $PROJECT_ID"
echo "     - GCP_ZONE        = $ZONE"
echo ""
echo "  2. Edit scripts/provision-vm.sh:"
echo "     change REPO_URL to your fork"
echo ""
echo "  3. Run provisioning:"
echo "     bash scripts/provision-vm.sh production"
echo "     bash scripts/provision-vm.sh staging"
echo "     bash scripts/provision-vm.sh dev"
echo ""
