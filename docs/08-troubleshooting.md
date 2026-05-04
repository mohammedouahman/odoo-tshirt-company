# 08 — Troubleshooting

## Odoo container won't start

```bash
sudo docker logs odoo_app_prod --tail=200
```

**Common causes:**
- DB not ready yet → wait 30 sec, restart: `sudo docker restart odoo_app_prod`
- Bad addon → check `addons_path` and module syntax
- Out of memory → check `free -h`; reduce `workers` in odoo.conf

## "Database connection refused"

The internal Docker network may not be up. Restart the stack:
```bash
cd /opt/odoo-tshirt-company
sudo docker compose -f docker/docker-compose.production.yml down
sudo docker compose -f docker/docker-compose.production.yml up -d
```

## Module changes not taking effect

Module needs to be **upgraded** in Odoo, not just deployed:
```bash
sudo docker exec odoo_app_prod \
    odoo --stop-after-init -u tshirt_branding -d tshirt_prod
sudo docker restart odoo_app_prod
```

## "502 Bad Gateway" from Nginx

Odoo isn't responding. Check:
```bash
sudo docker ps                         # is odoo container running?
sudo docker logs odoo_app_prod        # any errors?
sudo docker exec odoo_app_prod curl http://localhost:8069/web/login
```

## SSL certificate issues

If using Let's Encrypt and renewal fails:
```bash
sudo certbot renew --dry-run
sudo systemctl restart nginx
```

## Disk full

Odoo logs and Docker images can grow:
```bash
df -h
sudo docker system prune -af --volumes    # ⚠ also removes stopped volumes
sudo find /var/log -type f -name "*.log" -size +100M
```

## Postgres performance slow

```bash
sudo docker exec odoo_db_prod psql -U odoo postgres -c \
    "SELECT pid, now() - query_start AS duration, query \
     FROM pg_stat_activity \
     WHERE state = 'active' \
     ORDER BY duration DESC LIMIT 10;"
```

## Forgot Odoo master password

It's in the VM's `.env` file:
```bash
gcloud compute ssh odoo-production --tunnel-through-iap --zone=europe-west1-b
sudo grep ODOO_ADMIN_PASSWORD /opt/odoo-tshirt-company/.env
```

## GitHub Actions deploy fails with "Permission denied"

Service account needs the IAP role:
```bash
gcloud projects add-iam-policy-binding tshirt-odoo-prod \
    --member="serviceAccount:odoo-deployer@tshirt-odoo-prod.iam.gserviceaccount.com" \
    --role="roles/iap.tunnelResourceAccessor"
```

## Want a fresh Odoo database

```bash
sudo docker exec odoo_db_prod \
    psql -U odoo -d postgres -c "DROP DATABASE tshirt_prod;"
# then visit /web/database/manager and create fresh
```

## Can't connect via IAP SSH

Make sure the firewall rule exists:
```bash
gcloud compute firewall-rules list | grep iap
```
If missing, re-run: `bash scripts/setup-gcp-project.sh`
