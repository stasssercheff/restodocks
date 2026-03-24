# Security Rollout Plan (Staging -> Prod, No Downtime)

## Goals

- Max hardening with minimal functional risk.
- Zero downtime for web, iOS, and Yandex channels.
- No changes to ML parsing logic in this rollout.

## Phase 1: Staging validation

1. Apply SQL migrations in staging.
2. Deploy edge function hardening in staging.
3. Run regression test suite:
   - `docs/security/rls_idor_regression_test.sql`
   - `docs/security/rls_rpc_permissions_regression_test.sql`
4. Manual smoke tests:
   - login (owner/employee),
   - checklist save,
   - order document save + email send,
   - co-owner invite/accept flow,
   - nomenclature and TTK screens.
5. Load/abuse tests (lightweight):
   - burst requests on protected endpoints to verify `429`.

## Phase 2: Production rollout (safe window)

1. Schedule low-traffic release window.
2. Release order:
   - SQL migration first,
   - edge functions second,
   - web/app build last.
3. Keep rollback ready:
   - previous function versions,
   - migration rollback statements where possible,
   - backup snapshot references.

## Phase 3: Post-release monitoring

- Monitor for 60 minutes:
  - 4xx/5xx spikes,
  - auth failures,
  - email send failures,
  - checklist/order save failures.
- Then 24-hour watch:
  - request-rate anomalies,
  - suspicious endpoint bursts,
  - cross-tenant access logs.

## Rollback criteria

- >2x baseline error rate for critical flows.
- login or save operations failing for >5 minutes.
- confirmed false-positive blocking of core users.

If rollback triggers:
- revert edge function deploy first,
- then revert web/app if needed,
- keep SQL hardening if safe; otherwise apply prepared SQL rollback for affected object only.
