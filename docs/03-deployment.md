# 03 — Deployment

Deployment is fully automated by GitHub Actions. See [04-cicd-workflow.md](04-cicd-workflow.md) for the pipeline details, and [06-development-workflow.md](06-development-workflow.md) for daily-use commands.

## Manual Deployment (Emergency Only)

If GitHub Actions is broken:
```bash
gcloud compute ssh odoo-production --tunnel-through-iap --zone=europe-west1-b
cd /opt/odoo-tshirt-company
sudo bash scripts/deploy.sh production
```

## First Deploy Checklist

- [ ] GCP project created + billing enabled
- [ ] `setup-gcp-project.sh` ran successfully
- [ ] GitHub secrets configured (`GCP_SA_KEY`, `GCP_PROJECT_ID`, `GCP_ZONE`)
- [ ] All 3 VMs provisioned via `provision-vm.sh`
- [ ] Each VM completed bootstrap (`/var/log/startup.log` shows "complete")
- [ ] Database created on each environment via web UI
- [ ] T-Shirt Branding module installed
- [ ] First test order placed end-to-end

## Rollback

If a deploy breaks production:
```bash
gcloud compute ssh odoo-production --tunnel-through-iap --zone=europe-west1-b
cd /opt/odoo-tshirt-company
sudo git log --oneline -10            # find the last good commit
sudo git reset --hard <COMMIT_HASH>
sudo bash scripts/deploy.sh production
```

If the DB is corrupted, restore from backup — see [05-backup-recovery.md](05-backup-recovery.md).
