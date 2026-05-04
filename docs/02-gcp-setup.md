# 02 — GCP Setup (From Zero)

This guide takes you from "I just signed up for GCP free trial" → "all 3 Odoo environments are running."

**Total time:** ~30 minutes (most of it waiting for VMs to boot).

---

## Step 1 — Install gcloud CLI on Your Laptop

### macOS
```bash
brew install --cask google-cloud-sdk
```

### Ubuntu / Debian
```bash
sudo apt-get install apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install google-cloud-cli
```

### Windows
Download installer: https://cloud.google.com/sdk/docs/install

### Verify
```bash
gcloud --version
```

---

## Step 2 — Login & Create Project

```bash
gcloud auth login
gcloud auth application-default login

# Create a brand-new project (recommended — clean billing)
gcloud projects create tshirt-odoo-prod \
    --name="T-Shirt Odoo Production"

# Link it to your billing account (required even on free trial)
gcloud beta billing accounts list
gcloud beta billing projects link tshirt-odoo-prod \
    --billing-account=YOUR_BILLING_ACCOUNT_ID

gcloud config set project tshirt-odoo-prod
```

---

## Step 3 — Clone This Repo & Run the Setup

```bash
git clone https://github.com/YOUR_USER/odoo-tshirt-company.git
cd odoo-tshirt-company
chmod +x scripts/*.sh

# Edit if you want different region/zone
export GCP_PROJECT_ID=tshirt-odoo-prod
export GCP_REGION=europe-west1
export GCP_ZONE=europe-west1-b

bash scripts/setup-gcp-project.sh
```

This script will:
- ✅ Enable all required GCP APIs
- ✅ Create a service account for GitHub Actions
- ✅ Generate a key file for that service account
- ✅ Create a GCS bucket for backups (with 30-day lifecycle)
- ✅ Set up firewall rules

---

## Step 4 — Push This Repo to Your Own GitHub

```bash
gh repo create odoo-tshirt-company --private --source=. --remote=origin --push
# Or manually create on github.com and:
git remote add origin https://github.com/YOUR_USER/odoo-tshirt-company.git
git push -u origin main

# Create the staging and dev branches
git checkout -b staging && git push -u origin staging
git checkout -b dev && git push -u origin dev
git checkout main
```

---

## Step 5 — Add GitHub Secrets

Go to: `https://github.com/YOUR_USER/odoo-tshirt-company/settings/secrets/actions`

Add these secrets:

| Secret Name | Value |
|---|---|
| `GCP_SA_KEY` | Paste contents of `secrets/odoo-deployer-key.json` |
| `GCP_PROJECT_ID` | `tshirt-odoo-prod` |
| `GCP_ZONE` | `europe-west1-b` |

---

## Step 6 — Set GitHub Environment Approvals

For production safety, require manual approval before deploys:

1. Go to: `Settings → Environments → New environment`
2. Create three environments: `production`, `staging`, `dev`
3. For `production`, enable **"Required reviewers"** and add yourself
4. Now every prod deploy will pause until you click ✓

---

## Step 7 — Provision the VMs

```bash
# Update REPO_URL in scripts/provision-vm.sh first!
# Then:
export REPO_URL=https://github.com/YOUR_USER/odoo-tshirt-company.git

bash scripts/provision-vm.sh production
# wait ~5 minutes...
bash scripts/provision-vm.sh staging
# wait ~5 minutes...
bash scripts/provision-vm.sh dev
```

Each script prints the external IP at the end, e.g.:
```
External IP: 34.123.45.67
URL:         http://34.123.45.67.nip.io
```

---

## Step 8 — Watch the Bootstrap

The VMs run a startup script that installs Docker, clones the repo, and starts Odoo.

```bash
# Track production bootstrap progress
gcloud compute ssh odoo-production \
    --zone=europe-west1-b \
    --tunnel-through-iap \
    --command='sudo tail -f /var/log/startup.log'
```

When you see `===== Bootstrap complete =====`, Odoo is ready.

---

## Step 9 — First Login

Open the URL in your browser:
```
http://<EXTERNAL_IP>.nip.io
```

You'll see Odoo's database creation screen.

**Database Master Password** — get it from the VM:
```bash
gcloud compute ssh odoo-production \
    --zone=europe-west1-b \
    --tunnel-through-iap \
    --command='sudo grep ODOO_ADMIN_PASSWORD /opt/odoo-tshirt-company/.env'
```

Create your first DB:
- **Master Password:** (from above)
- **Database Name:** `tshirt_prod`
- **Email:** your email
- **Password:** strong password
- **Demo data:** ✅ Yes (for first run; uncheck in real production)

---

## Step 10 — Verify

You should land on the Odoo dashboard. Install the custom module:
1. Apps menu → Search "T-Shirt"
2. Click **Install** on "T-Shirt Branding Manager"

You're live! 🎉

---

## Troubleshooting

**VM created but Odoo not responding?**
```bash
gcloud compute ssh odoo-production --tunnel-through-iap --zone=europe-west1-b
sudo docker ps                              # see running containers
sudo docker logs odoo_app_prod --tail=100   # see Odoo logs
sudo cat /var/log/startup.log               # see bootstrap log
```

**Need to restart everything on a VM?**
```bash
cd /opt/odoo-tshirt-company
sudo docker compose -f docker/docker-compose.production.yml restart
```
