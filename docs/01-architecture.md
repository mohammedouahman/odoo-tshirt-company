# 01 — Architecture

## Why This Design

This setup mirrors **Odoo.sh** capabilities using only open-source components on GCP. The goal: a **professional, reproducible, cost-controlled** environment where the workflow feels like Odoo.sh but you own everything.

## The Three Environments

| Environment | Purpose | Branch | VM Size | Mail |
|---|---|---|---|---|
| **Production** | Live system, real customers, real money | `main` | e2-standard-2 (8GB) | Real SMTP (Brevo) |
| **Staging** | Test changes against a copy of prod data | `staging` | e2-medium (4GB) | MailHog (catcher) |
| **Development** | Active coding, breaking things OK | `dev` | e2-small (2GB) | MailHog (catcher) |

## How a Change Flows from Idea to Production

```
1. Developer creates feature branch from dev
       │
       ▼
2. Codes locally → pushes to feature branch
       │
       ▼
3. Opens PR → GitHub Actions runs tests automatically
       │
       ▼
4. PR merged into dev → auto-deploys to dev VM
       │
       ▼
5. Tested on dev → PR opened from dev → staging
       │
       ▼
6. Merged to staging → auto-deploys + restored prod backup for testing
       │
       ▼
7. Validated on staging → PR opened from staging → main
       │
       ▼
8. Manual approval in GitHub → deploys to PRODUCTION
```

## What Runs on Each VM

```
┌─────────────────────────────────────────┐
│  PRODUCTION VM (e2-standard-2)           │
├─────────────────────────────────────────┤
│  Docker Compose stack:                   │
│  ┌──────────────────────────────────┐   │
│  │ nginx (80, 443)                  │   │
│  │   ↓ proxies                      │   │
│  │ odoo (8069, 8072)                │   │
│  │   ↓ talks to                     │   │
│  │ postgres (internal network only) │   │
│  └──────────────────────────────────┘   │
│  + cron: daily backup → GCS              │
│  + ufw firewall                          │
│  + fail2ban                              │
└─────────────────────────────────────────┘
```

Staging adds `mailhog`. Dev adds `mailhog` + `pgadmin` + exposes ports for direct local debugging.

## Networking

- **Production / Staging:** Postgres is on a Docker internal network — **never reachable from outside the VM**.
- **Dev:** Postgres port 5432 exposed for direct pgAdmin access from your laptop.
- **All VMs:** Only ports 22 (SSH via IAP), 80, 443 open to the internet.
- **Dev only:** ports 8069, 8025, 5050 also open (Odoo direct, MailHog UI, pgAdmin).

## Data Persistence

| Path | What | Backed Up? |
|---|---|---|
| Docker volume `postgres_data` | PostgreSQL data | ✅ Daily pg_dump → GCS |
| Docker volume `odoo_data` | Filestore (uploaded files) | ✅ Daily tar.gz → GCS |
| `/opt/odoo-tshirt-company/.env` | Secrets | ❌ Only on the VM (regenerate if lost) |
| `/opt/odoo-tshirt-company/custom_addons/` | Your code | ✅ It's in git |

## Cost Control Strategies

1. **Stop staging/dev VMs when not in use** — saves ~$40/month
   ```bash
   gcloud compute instances stop odoo-staging odoo-dev --zone=europe-west1-b
   ```
2. **Use sustained-use discounts** — automatic on GCP, ~30% off after a month
3. **GCS autoclass** — backups auto-tier to cold storage after 30 days
4. **Free tier resources** — Cloud Logging, Monitoring, DNS within free quota
