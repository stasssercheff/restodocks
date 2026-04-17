# Supabase Stress Test (No AI)

This test intentionally avoids AI/LLM functions and focuses on database endurance.

## What it does

- Creates 1 synthetic establishment
- Creates `N` auth users + employees (default 100)
- Inserts `N` tech cards (default 1000)
- Inserts `N` inventory documents (default 10)
- Distributes records across multiple languages
- Performs language-switch churn updates on employees
- Runs concurrent read probes on `tech_cards`
- Prints timing metrics and a ready-to-run cleanup command

All synthetic records are marked with a unique `run_id` in names/emails/payload.

## Safety guard

The script refuses to run unless you explicitly confirm:

`STRESS_CONFIRM=YES_I_UNDERSTAND_THIS_IS_STAGING_LOAD_TEST`

## Required env

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

## Run example

```bash
STRESS_CONFIRM=YES_I_UNDERSTAND_THIS_IS_STAGING_LOAD_TEST \
STRESS_EMPLOYEES=100 \
STRESS_TECH_CARDS=1000 \
STRESS_INVENTORIES=10 \
STRESS_LANGS=ru,en,es,it,tr,vi,de,fr \
STRESS_LANGUAGE_SWITCH_OPS=300 \
STRESS_CONCURRENCY=8 \
node scripts/supabase_stress_no_ai.js
```

Language behavior:
- employee `preferred_language` is assigned cyclically from `STRESS_LANGS`
- `tech_cards.dish_name_localized` is filled when that column exists
- churn phase executes repeated language switches (`STRESS_LANGUAGE_SWITCH_OPS`)

## Cleanup example

Use `runId` from the script output.

```bash
STRESS_MODE=cleanup \
STRESS_CLEANUP_RUN_ID=stress_20260413153000 \
STRESS_CONFIRM=YES_I_UNDERSTAND_THIS_IS_STAGING_LOAD_TEST \
node scripts/supabase_stress_no_ai.js
```

## Suggested Supabase checks during test

- Dashboard:
  - Database CPU
  - Active connections
  - API latency p95/p99
  - Error rate (4xx/5xx)
- Query Performance:
  - Most frequent queries
  - Slow queries / lock waits
