# 06 — Development Workflow (Day-to-Day)

## The Mental Model

This setup is **GitHub-driven**. You don't ssh into VMs and edit code there — you edit locally, push to git, and the VM auto-updates.

```
Your laptop       →  GitHub        →  VM
(write code)         (push)            (auto-deploy)
```

---

## Daily Development Loop

### 1. Pull Latest Code
```bash
git checkout dev
git pull
```

### 2. Create a Feature Branch
```bash
git checkout -b feature/lead-scoring-tweaks
```

### 3. Edit Code Locally
Open `custom_addons/tshirt_branding/` in VS Code or Cursor.
Edit the Python / XML / JS files.

### 4. Test Locally (Optional but Recommended)
You can run the entire stack on your laptop:
```bash
cp .env.example .env
# Edit .env — set passwords to anything for local
docker compose -f docker/docker-compose.dev.yml up -d
```
Open `http://localhost:8069` — you have a full Odoo running on your machine.

### 5. Commit & Push
```bash
git add .
git commit -m "feat(crm): adjust lead scoring weights for B2B"
git push -u origin feature/lead-scoring-tweaks
```

### 6. Open a Pull Request
- Open PR: `feature/lead-scoring-tweaks` → `dev`
- GitHub Actions automatically runs lint + module tests
- Review the diff yourself
- Merge → **dev VM auto-updates within ~30 seconds**

### 7. Test on Dev VM
Visit `http://<DEV_VM_IP>.nip.io` — your changes are live.

### 8. Promote to Staging
When dev looks good:
```bash
git checkout staging
git merge dev
git push
```
→ staging VM auto-updates.

### 9. Test on Staging Against Prod Data
On staging, restore the latest prod backup:
```bash
gcloud compute ssh odoo-staging --tunnel-through-iap --zone=europe-west1-b
cd /opt/odoo-tshirt-company
sudo bash scripts/restore.sh staging $(date -u +%Y%m%d)_030000 tshirt_prod
```
Now staging has **real production data** to test against.

### 10. Promote to Production
When staging is verified:
```bash
git checkout main
git merge staging
git push
```
GitHub Actions will pause — go to the Actions tab and **click Approve**.
Production deploys.

---

## Common Tasks

### See Live Logs of Any Environment
```bash
gcloud compute ssh odoo-<env> --tunnel-through-iap --zone=europe-west1-b
sudo docker logs -f odoo_app_<env>
```

### Get a Web Shell (Odoo.sh-Style)
```bash
gcloud cloud-shell ssh
gcloud compute ssh odoo-production --tunnel-through-iap --zone=europe-west1-b
sudo docker exec -it odoo_app_prod bash
```
Now you're inside the Odoo container.

### Drop Into the Postgres Console
```bash
sudo docker exec -it odoo_db_prod psql -U odoo postgres
```

### Update a Specific Module Without Redeploying Everything
```bash
sudo docker exec odoo_app_prod \
    odoo --stop-after-init -u tshirt_branding -d tshirt_prod
```

### Read Mail Sent on Staging (MailHog)
Visit: `http://<STAGING_IP>.nip.io/mail/`
Login: `mailadmin` / (password generated at provision time, in `/opt/odoo-tshirt-company/config/nginx/.htpasswd`)

### Hot-Reload Custom Code on Dev
The dev VM mounts `custom_addons/` writable. Edit on the VM directly:
```bash
sudo docker exec odoo_app_dev kill -HUP 1   # tells Odoo to reload
```
Or just restart:
```bash
sudo docker restart odoo_app_dev
```

---

## Branch Strategy Summary

| Branch | Auto-deploys to | Purpose |
|---|---|---|
| `feature/*` | Nowhere | Your work-in-progress |
| `dev` | Dev VM | Integration testing |
| `staging` | Staging VM | UAT with prod-like data |
| `main` | Production VM (after approval) | Live |

**Rule:** Never commit directly to `main` or `staging`. Always go through PR.
