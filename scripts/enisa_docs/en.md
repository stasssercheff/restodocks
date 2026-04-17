# Restodocks — Technical Description (ENISA / Startup Visa)

## 1. System architecture

### 1.1 Client tier

- Primary client: Flutter 3.x (Dart SDK ≥3.5), single codebase for iOS, Android, and Web (supabase_flutter, go_router, provider).
- Local persistence: shared_preferences, SQLite (sqflite) for large JSON snapshots, plus offline-oriented services (offline cache, establishment hydration).
- Networking: Supabase client with retrying HTTP layer; realtime subscriptions on `tech_cards` and `products` with debounced refresh (~700 ms) and periodic fallback.

### 1.2 Backend tier

- BaaS: Supabase — PostgreSQL, PostgREST, Auth (JWT sessions), Row Level Security (RLS), Realtime, Storage, Edge Functions (Deno/TypeScript).
- Operational APIs: Edge Functions for AI parsing, procurement receipts, billing (e.g. Apple IAP verification), email flows.
- Admin: separate Next.js application (API routes, server-side Supabase) for operational tasks — not the main restaurant UI.

### 1.3 Hybrid data model

- Authoritative store: PostgreSQL — relational tables for tenants (establishments), employees, products, nomenclature prices (`establishment_products`), tech card headers (`tech_cards`), normalized ingredient lines (`tt_ingredients`), procurement documents, translations, fiscal settings.
- Structured blobs: JSON/JSONB where appropriate (e.g. tech card sections, document payloads).
- Client mapping: Flutter domain models map rows into in-memory graphs; food cost is often derived at read time from current prices and recipe structure.
- Caching: in-memory product/price caches, TTL-based refresh, establishment-scoped hydration — offline-first UX with server reconciliation.

This is a hybrid relational + document-style design: normalized where integrity matters; flexible JSON where UI blocks need it.

---

## 2. Dynamic food cost — core algorithm

### 2.1 Source of truth

- Per-establishment unit prices: `establishment_products` (price + currency), updated via upsert on `(establishment_id, product_id)`.
- Price history: `product_price_history` when the effective price changes beyond a small epsilon (0.001).

### 2.2 Procurement → price updates

- Procurement receipt lines include received quantity, actual price per unit, and discount %.
- Effective unit price = actualPrice × (1 − discount/100).
- Lines differing from current nomenclature prices are collected; depending on policy, Edge workflows or on-device approval dialogs apply; selected lines update `setEstablishmentPrice` for the nomenclature establishment (shared-catalog pattern supported).

### 2.3 Tech card “recalculation”

- Recipes reference products and semi-finished cards (`sourceTechCardId`).
- Displayed food cost uses hydration: `TechCardCostHydrator` resolves leaf rows from `getEstablishmentPrice` (fallback `basePrice`), converts gross/net/pcs to kg-equivalent quantity, sets cost = pricePerKg × qty.
- Nested semi-finished: recursive resolution with cycle protection (memo + resolving set); nested output grams and nested cost imply price per kg for the parent line.
- UI layers (e.g. Excel-style TTK) mirror the same resolution for consistency.

Changing an invoice price does not batch-update all tech cards in SQL; it updates `establishment_products`. The next load, realtime refresh, or hydration pass recomputes costs — low write amplification, no stale single aggregate column.

### 2.4 Performance and numerical behaviour

- Complexity: O(ingredients × nesting depth) with memoization for nested cards.
- Latency: dominated by network fetch and JSON decode, not arithmetic (Dart double).
- Accuracy: IEEE-754 doubles; price equality uses epsilon 0.001; g↔kg via /1000 — suitable for operational costing, not certified statutory audit precision.

### 2.5 Edge cases

- Missing price: cost remains zero or unchanged until priced.
- Piece units (`pcs` / `шт`): `gramsPerPiece` (default 50 g) for mass-based cost.
- Currency: stored per line; cross-currency rollups are not assumed without explicit FX rules.

---

## 3. Technological innovation

### 3.1 AI in production

- Edge Functions: LLM-backed receipt and tech-card image → structured JSON (vision models via shared provider layer); batch extraction, PDF parsing, product-list parsing, duplicate detection, checklist generation.
- API keys remain server-side (Edge/Vault); Flutter invokes functions only.
- On-device OCR (mobile): Google ML Kit + Apple Vision for low-latency capture without a server round-trip.

### 3.2 Engineering scalability

- LLM/OCR providers are swappable behind function boundaries without rewriting the Flutter domain layer (documented integration patterns in-repo).

### 3.3 Multilingual architecture

- UI: single `localizable.json` keyed by language; `LocalizationService` — keys in code, strings in assets; `intl` for formatting.
- Implemented UI locales: nine (`ru`, `en`, `es`, `kk`, `de`, `fr`, `it`, `tr`, `vi`).
- Domain content (products, tech cards): `TranslationManager` + `TranslationService` — persisted translations, optional Google Cloud Translation / MyMemory / AI backends, manual overrides.
- Maintenance scripts for key parity across languages. Native app builds bundle translations; web can pick up JSON on deploy.

---

## 4. Security and GDPR-oriented design

### 4.1 Authentication

- Supabase Auth — JWT sessions; email confirmation deep links (implicit flow where applicable).

### 4.2 Authorization

- RLS on tenant tables; policies for authenticated roles and establishment-scoped predicates.
- RPC `check_establishment_access(establishment_id)` centralizes subscription/promo/entitlement checks; hardened GRANT/REVOKE in migrations.
- Sensitive workflows (procurement, order documents) use Edge Functions for server-side validation and service-role operations where needed.

### 4.3 GDPR-relevant notes (technical)

- Multilingual privacy policy text in-app (`legal_texts.dart`).
- Multi-tenant model with per-establishment data scoping.
- Retention: policy references legal/accounting retention; operational backup/export policies are organizational.

---

## 5. Scalability and new markets

### 5.1 Currency

- Establishment default currency and per-line nomenclature currency; centralized currency option lists (ISO codes, symbols) — extending markets is primarily data + UX, not a schema rewrite.

### 5.2 Tax (VAT / IVA / regional)

- Fiscal presets: versioned JSON (`world_tax_presets.json`) — regions with VAT rate lists, default VAT %, price tax mode (`tax_included` / `tax_excluded`), optional extra taxes.
- Per-establishment overrides: region code, VAT override, price tax mode; `effectiveVatPercent` resolves preset ± override.
- Adding a new jurisdiction (e.g. Spain / IVA): add a region block, labels, and translations — incremental content work on top of the existing fiscal module.

### 5.3 Load

- PostgreSQL + Edge scale with standard patterns (pooling, replicas if used).
- Client debouncing and TTL caches reduce read storms under many concurrent devices.

---

## 6. Operational readiness

- Versioned SQL migrations; i18n tooling; Edge logging (`log-system-error`); Apple billing verification.
- POS fiscal hardware driver not connected in code (`isKktDriverConfigured == false`) — fiscal outbox exists; full KKT integration is a separate milestone.

---

*Document generated from the Restodocks codebase structure (Flutter + Supabase). Technical description for ENISA / Startup Visa submission.*
