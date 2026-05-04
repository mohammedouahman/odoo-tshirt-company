# Odoo 18 — T-Shirt Branding Company
### Production-Grade Self-Hosted Setup on GCP (Odoo.sh-Equivalent Architecture)

A complete, professional Odoo 18 deployment that mimics Odoo.sh capabilities:
**Production + Staging + Development environments**, GitHub-driven CI/CD, automated backups, mail catcher, and a custom T-shirt branding business module.

---

## 🎯 What This Project Delivers

| Odoo.sh Feature | Our Equivalent |
|---|---|
| Production / Staging / Dev branches | 3 GCP VMs, each tied to a Git branch |
| Auto-deploy on push | GitHub Actions CI/CD |
| Web Shell | GCP Cloud Shell + `docker exec` |
| Detailed logs | Docker logs + Loki (optional) |
| Mail Catcher (staging/dev) | MailHog container |
| SSH access | GCP IAM-managed SSH keys |
| Daily incremental backups | `pg_dump` → GCS, 30-day retention |
| Automated tests | GitHub Actions on every PR |
| Module dependency management | Git submodules + `requirements.txt` |
| Instant recovery | One-command restore script |
| DNS | Free `nip.io` subdomains |
| Top-notch security | UFW, fail2ban, Let's Encrypt, isolated networks |

---

## 🏗️ Architecture Overview

```
                    ┌──────────────────┐
                    │  GitHub Repo     │
                    │  main / staging  │
                    │  / dev branches  │
                    └────────┬─────────┘
                             │
                  GitHub Actions CI/CD
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
  ┌──────────┐         ┌──────────┐         ┌──────────┐
  │   PROD   │         │ STAGING  │         │   DEV    │
  │ e2-std-2 │         │ e2-med   │         │ e2-small │
  │ 8GB RAM  │         │ 4GB RAM  │         │ 2GB RAM  │
  └────┬─────┘         └────┬─────┘         └────┬─────┘
       │                    │                    │
       └─────────┬──────────┴────────────────────┘
                 ▼
       ┌──────────────────┐
       │ GCS Backups      │
       │ Cloud Monitoring │
       │ Cloud DNS (opt.) │
       └──────────────────┘
```

---

## 📚 Documentation Index

Read in this order:

1. **[01-architecture.md](docs/01-architecture.md)** — Why this design, what runs where
2. **[02-gcp-setup.md](docs/02-gcp-setup.md)** — Provision GCP resources from zero
3. **[03-deployment.md](docs/03-deployment.md)** — Deploy Odoo to all 3 environments
4. **[04-cicd-workflow.md](docs/04-cicd-workflow.md)** — GitHub → Server pipeline
5. **[05-backup-recovery.md](docs/05-backup-recovery.md)** — Backup strategy + restore drills
6. **[06-development-workflow.md](docs/06-development-workflow.md)** — How to work day-to-day
7. **[07-tshirt-business-config.md](docs/07-tshirt-business-config.md)** — Configure the business
8. **[08-troubleshooting.md](docs/08-troubleshooting.md)** — Common issues + fixes

---

## 🚀 Quick Start (TL;DR)

```bash
# 1. Clone this repo locally
git clone https://github.com/YOUR_USER/odoo-tshirt-company.git
cd odoo-tshirt-company

# 2. Provision GCP (one-time)
bash scripts/setup-gcp-project.sh

# 3. Provision the 3 VMs
bash scripts/provision-vm.sh production
bash scripts/provision-vm.sh staging
bash scripts/provision-vm.sh dev

# 4. Push to trigger first deploy
git push origin main      # → deploys to production
git push origin staging   # → deploys to staging
git push origin dev       # → deploys to dev
```

---

## 💰 Estimated Monthly Cost (GCP)

| Resource | Cost |
|---|---|
| Production VM (e2-standard-2) | ~$50/mo |
| Staging VM (e2-medium) | ~$25/mo |
| Dev VM (e2-small) | ~$13/mo |
| Cloud Storage (50GB backups) | ~$1/mo |
| Network egress (light) | ~$5/mo |
| **TOTAL** | **~$95/mo** |

With your $300 free credit: **~3 months runway**, or **5+ months** if you stop staging/dev when not in use.

---

## 🔐 Security Defaults

- Firewall: only ports 22 (SSH), 80, 443 open to internet
- PostgreSQL: bound to Docker network only, never exposed
- Odoo admin password: random 32-char, stored in GCP Secret Manager
- SSH: key-only, no passwords
- Automated security updates via `unattended-upgrades`
- HTTPS enforced via Let's Encrypt (when domain provided)

---

## 📞 Support

This setup uses **only open-source components**. No vendor lock-in.
For Odoo questions: https://www.odoo.com/documentation/18.0/

---

**Built for the T-Shirt Branding Company use case** — fully replicable for any SMB.
