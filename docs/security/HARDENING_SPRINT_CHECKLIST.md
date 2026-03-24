# Security Hardening Sprint Checklist

This checklist is scoped for Restodocks web, iOS app, and Yandex-related entry points.
Goal: maximize protection without breaking business flows.

## 1) Edge/API gateway hardening

- [ ] Turn on JWT verification for every mutating Edge Function that does not require anonymous access.
- [ ] For anonymous-required endpoints, enforce:
  - [ ] `apikey` validation server-side.
  - [ ] strict CORS allowlist via `RD_ALLOWED_ORIGINS`.
  - [ ] per-IP + per-endpoint rate limiting.
- [ ] Deny unexpected methods and oversized payloads.
- [ ] Remove wildcard CORS from sensitive endpoints.

## 2) Database authorization (RLS + RPC)

- [ ] Audit all `SECURITY DEFINER` functions:
  - [ ] verify caller context (`auth.uid()` where possible),
  - [ ] remove trust in client-supplied IDs,
  - [ ] `REVOKE EXECUTE ... FROM PUBLIC`.
- [ ] Remove broad policies like `USING (true)` on tenant data tables.
- [ ] Add tenant checks for every write path (`establishment_id` ownership).
- [ ] Run cross-tenant negative tests (`SELECT/UPDATE/DELETE` should fail).

## 3) Token and invitation security

- [x] Replace predictable invitation token generation with cryptographically secure random token.
- [x] Remove sensitive establishment fields from anonymous invitation lookup payload.
- [ ] Add invitation TTL enforcement + one-time-use invalidation checks.
- [ ] Store token hash (not plain token) if migration complexity allows.

## 4) Anti-scraping and abuse controls

- [ ] Cloudflare WAF managed rules enabled for production and beta.
- [ ] Dedicated rate-limit rules for:
  - `/functions/v1/send-email`,
  - `/functions/v1/send-registration-email`,
  - auth/password reset endpoints,
  - AI-heavy endpoints.
- [ ] Alerting for spikes in 4xx/5xx and request volume anomalies.

## 5) Secrets and backup hardening

- [ ] Exclude secrets from automatic backup bundles by default.
- [ ] Encrypt backups at rest.
- [ ] Rotate compromised/old keys on schedule.
- [ ] Monthly restore drill with written pass/fail report.

## 6) Platform-specific notes (iOS / web / Yandex)

- iOS:
  - [ ] keep native requests functional when `Origin` header is absent.
  - [ ] prefer JWT-authenticated flows; fallback flows must be rate-limited.
- Web:
  - [ ] strict origin allowlist for browser clients.
  - [ ] no plaintext credentials in local storage.
- Yandex integration:
  - [ ] treat Yandex-origin traffic as explicit allowlist entries.
  - [ ] protect every integration endpoint with the same rate-limit/auth policy set.
