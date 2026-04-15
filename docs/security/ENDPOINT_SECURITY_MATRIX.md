# Endpoint Security Matrix

Scope: web, iOS app, and Yandex web entry points.

## Supabase Edge Functions

| Endpoint | Purpose | Auth Mode | Rate Limit | Ownership / Tenant Check |
|---|---|---|---|---|
| `send-email` | send order email | API key header required | 20/min/IP | server-side only (no DB write), send constraints |
| `send-registration-email` | registration and confirmation email | API key header required | 12/min/IP | no cross-tenant DB mutation; strict template flow |
| `save-checklist` | update checklist + items | API key header required | 60/min/IP | checklist existence + assignee belongs to checklist establishment |
| `save-order-document` | create order documents | API key header required | 40/min/IP | `createdByEmployeeId` must belong to `establishmentId` |
| `register-metadata` | registration geo metadata | API key header required | 20/min/IP | writes only selected establishment row |
| `tt-parse-save-learning` | parser learning persistence | API key header required | 25/min/IP | currently no ML-logic changes; write path protected by key/rate limits |
| `authenticate-employee` | legacy auth | legacy open in config | must be limited at edge | must remain compatible with legacy flow |
| `parse-ttk-by-templates` | parsing by templates | currently legacy/open in config | must be limited at edge | should be moved to verified JWT/API key model later |
| `auto-translate-product` | translation helper | currently legacy/open in config | must be limited at edge | should move to stricter caller validation |
| `fetch-nutrition-off` | OFF proxy | currently legacy/open in config | must be limited at edge | no tenant data write |
| `get-training-video-url` | training URL by geo | currently legacy/open in config | must be limited at edge | no tenant data write |

## Admin API (Next.js)

| Route | Required Auth | Current Risk | Required Control |
|---|---|---|---|
| `/api/auth` | admin login | brute-force on shared password flow | WAF + route rate-limit + lockout + MFA roadmap |
| `/api/establishments*` | admin session | high impact if session stolen | signed httpOnly session + strict origin + audit logs |
| `/api/promo` | admin session | abuse if auth bypassed | role check + request audit + rate-limit |

## DB/RLS verification targets

- `tech_cards`
- `tt_ingredients`
- `establishment_products`
- `order_documents`
- `inventory_documents`
- `checklists` / `checklist_items`
- `establishment_documents`
- invitation/token-related RPCs

All reads/writes must be tenant-scoped (`current_user_establishment_ids()` / `auth.uid()`-based checks).
