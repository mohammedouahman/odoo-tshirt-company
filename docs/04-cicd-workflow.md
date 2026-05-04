# 04 — CI/CD Workflow

## Pipeline Overview

```
git push  →  GitHub Actions  →  Tests  →  Deploy to VM  →  Health check
```

## Workflows

### `.github/workflows/ci-tests.yml`
Runs on **every PR and every push to dev**.

What it does:
1. Spins up a Postgres service container
2. Runs `flake8` and `pylint-odoo` on `custom_addons/`
3. Builds the custom Odoo Docker image
4. Installs the `tshirt_branding` module with `--test-enable`
5. Reports pass/fail back to GitHub

A failing test **blocks the PR** from being merged.

### `.github/workflows/deploy.yml`
Runs on **push to main, staging, or dev**.

What it does:
1. Authenticates to GCP using the service account key
2. SSH'es into the matching VM via IAP (no public SSH port needed)
3. Runs `scripts/deploy.sh` on the VM
4. Polls the public URL until Odoo responds healthy

For `main` (production), the workflow **pauses for manual approval** — set up at:
`Settings → Environments → production → Required reviewers`.

## Required GitHub Secrets

| Secret | Purpose |
|---|---|
| `GCP_SA_KEY` | Service account JSON key (entire file pasted) |
| `GCP_PROJECT_ID` | e.g. `tshirt-odoo-prod` |
| `GCP_ZONE` | e.g. `europe-west1-b` |

## Customizing the Pipeline

**Add Slack notifications on deploy failure:**
```yaml
- name: Notify Slack
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    channel-id: 'ops-alerts'
    slack-message: 'Production deploy FAILED! See ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}'
  env:
    SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```

**Add automatic backup before each prod deploy:**
Add a step before the deploy step:
```yaml
- name: Backup before deploy
  run: |
    gcloud compute ssh odoo-production --zone=$GCP_ZONE --tunnel-through-iap \
      --command="cd /opt/odoo-tshirt-company && sudo bash scripts/backup.sh"
```
