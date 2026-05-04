# 07 — T-Shirt Business Configuration

After Odoo is running, configure it for the T-shirt branding business in this order.

## Prerequisites

- Odoo 18 is running on production
- Custom module `T-Shirt Branding Manager` is installed
- You have admin access

---

## Step 1 — Install Required Standard Modules

Apps menu → Search & Install:

| Module | Why |
|---|---|
| **CRM** | Lead & opportunity management |
| **Sales** | B2B quotations + orders |
| **eCommerce** | B2C public website store |
| **Manufacturing (MRP)** | Production planning |
| **Inventory** | Stock + warehouse |
| **Timesheets** | Track time per production stage |
| **Accounting** | Invoicing + financials |
| **Website** | Public website builder |

---

## Step 2 — Configure Company

Settings → Companies → Your Company:
- Name, address, VAT number, logo
- Currency: MAD (Moroccan Dirham) — change if different
- Timezone: Africa/Casablanca

---

## Step 3 — Set Up Sales Teams

CRM → Configuration → Sales Teams:
- **B2B Team** — handles companies, custom orders
- **B2C Team** — handles website orders, individual customers

Assign salespeople to each.

---

## Step 4 — Configure the Website Store

Website → Configuration:
- Set domain (use your nip.io URL for now)
- Choose a theme
- Configure payment providers (Stripe, PayPal, or local Moroccan gateway like CMI)

Website → Products:
- Add T-shirt products (categories: Men, Women, Kids, Custom)
- Set "Can be Sold" + "Published on Website"

---

## Step 5 — Configure Lead Capture

Website → Apps → Online Form Builder:
- Create a "Get a Quote" form on your website
- Map form fields to CRM lead fields:
  - Company name → `partner_name`
  - Estimated quantity → `estimated_quantity`
  - Company size → `company_size_band`
  - Delivery timeframe → `desired_delivery_days`
- Submission creates a CRM lead with auto-calculated `tshirt_priority_score`

---

## Step 6 — Set Up Production Stages

T-Shirt Branding → Configuration → Production Stages:

The defaults are pre-loaded (Art Work → Proofing → Frame → Printing → QC → Done).
Adjust SLAs based on your real shop times:

| Stage | Default SLA | Adjust to your reality |
|---|---|---|
| Art Work | 48 h | |
| Proofing | 24 h | |
| Frame Making | 48 h | |
| Printing | 24 h | |
| QC | 12 h | |

---

## Step 7 — Configure Outgoing Email (Production Only)

Settings → Technical → Outgoing Mail Servers:

**Recommended: Brevo (formerly Sendinblue)** — free tier of 300 emails/day

| Field | Value |
|---|---|
| Description | Brevo SMTP |
| SMTP Server | `smtp-relay.brevo.com` |
| SMTP Port | `587` |
| Connection Security | TLS (STARTTLS) |
| Username | your Brevo SMTP login |
| Password | your Brevo SMTP key |

Test it → send a test email to yourself.

---

## Step 8 — Create User Accounts for the Team

Settings → Users & Companies → Users:

For each of the 15 employees:
- Set their access groups based on role:

| Role | Groups |
|---|---|
| Sales rep | Sales: User, CRM: User |
| Designer | T-Shirt Branding: User |
| Shop floor worker | T-Shirt Branding: User, Timesheets: User |
| Manager | T-Shirt Branding: Manager + all User groups |
| Accountant | Accounting: Accountant |
| Admin (founder) | Settings: Administrator |

---

## Step 9 — Test the Full Workflow

1. **Lead** — submit a fake lead via website form → check CRM Pipeline → verify priority score appears
2. **Quotation** — convert lead to opportunity → create quotation → upload a logo in the "Branding Details" tab → send to customer
3. **Confirm** — confirm the order → verify production order auto-created in T-Shirt Branding → Production
4. **Workflow** — drag the Kanban card through stages → log time at each stage
5. **Invoice** — create invoice from Sales Order → register payment
6. **Repeat** for B2C: place a website order → verify it appears in Sales + creates production order if branding info attached

---

## Step 10 — Daily KPIs to Watch

T-Shirt Branding → Dashboard:
- Total active production orders
- Orders late (over SLA)
- Hours per stage (employee efficiency)
- Quantity printed per day

CRM → Reporting:
- Hot leads not contacted in 24h
- Conversion rate per source
