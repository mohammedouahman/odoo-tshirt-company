# 05 — Backup & Recovery

## Strategy

| Aspect | Choice |
|---|---|
| **Frequency** | Daily at 03:00 UTC (configurable in cron) |
| **Method** | `pg_dump -Fc` (custom format) + filestore tarball |
| **Storage** | GCS bucket `<project>-backups`, regional |
| **Retention** | 30 days (auto-deleted after) |
| **Cost** | ~$1/month for typical SMB usage |

## What Gets Backed Up

For each environment:
1. **All non-template Postgres databases** (custom dumps, gzipped)
2. **Odoo filestore** (uploaded attachments, logos, etc.)
3. **A manifest.json** listing what's in this backup

## Verifying Backups Work

Always run a restore drill on **staging** at least once a month:

```bash
# 1. List recent backups
gcloud compute ssh odoo-staging --tunnel-through-iap --zone=europe-west1-b
cd /opt/odoo-tshirt-company
sudo bash scripts/restore.sh
# (no args = lists available backups)

# 2. Restore the latest prod backup to staging
sudo bash scripts/restore.sh staging 20260503_030000 tshirt_prod

# 3. Open staging in browser, verify the data is there
```

## Disaster Recovery Drill

Once per quarter, simulate "production VM exploded":

```bash
# Pretend prod is gone
gcloud compute instances delete odoo-production --zone=europe-west1-b

# Re-provision (takes ~5 min)
bash scripts/provision-vm.sh production

# Wait for bootstrap, then restore latest backup
gcloud compute ssh odoo-production --tunnel-through-iap --zone=europe-west1-b
cd /opt/odoo-tshirt-company
sudo bash scripts/restore.sh production 20260503_030000 tshirt_prod
```

**Target Recovery Time Objective (RTO):** 30 minutes
**Recovery Point Objective (RPO):** 24 hours (daily backups)

To improve RPO, change cron in `provision-vm.sh` to run hourly:
```
0 * * * * root /opt/odoo-tshirt-company/scripts/backup.sh
```

## Manual Backup (Right Now)

```bash
gcloud compute ssh odoo-production --tunnel-through-iap --zone=europe-west1-b
cd /opt/odoo-tshirt-company
sudo bash scripts/backup.sh
```

## Download a Backup to Your Laptop

```bash
gsutil ls gs://tshirt-odoo-prod-backups/production/
gsutil -m cp -r gs://tshirt-odoo-prod-backups/production/20260503_030000/ ./local-backup/
```
