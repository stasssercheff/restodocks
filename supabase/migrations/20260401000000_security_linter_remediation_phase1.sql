-- Phase 1 remediation for Supabase security linter findings.
-- Safe/idempotent fixes only:
-- 1) Ensure RLS is enabled on tables that already have policies.
-- 2) Fix mutable function search_path warnings for selected public functions.

-- ERROR fixes: policies exist but RLS disabled.
ALTER TABLE IF EXISTS public.checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.checklist_items ENABLE ROW LEVEL SECURITY;

-- WARN fixes: function_search_path_mutable.
-- We use dynamic ALTER FUNCTION by OID to avoid hardcoding signatures.
DO $$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS regproc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        '_auth_user_establishment_ids',
        'insert_iiko_products',
        'get_iiko_products',
        'delete_iiko_products',
        'check_establishment_access',
        'check_promo_code',
        'use_promo_code',
        'check_employee_limit',
        'check_parent_is_main'
      )
  LOOP
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path TO pg_catalog, public',
      fn.regproc
    );
  END LOOP;
END
$$;

-- WARN fix: extension_in_public.
-- Some managed extensions (including pg_net on Supabase) may not support SET SCHEMA.
-- Try to move, but do not fail migration if unsupported.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'pg_net'
      AND n.nspname = 'public'
  ) THEN
    CREATE SCHEMA IF NOT EXISTS extensions;
    BEGIN
      ALTER EXTENSION pg_net SET SCHEMA extensions;
    EXCEPTION
      WHEN feature_not_supported THEN
        RAISE NOTICE 'pg_net does not support SET SCHEMA on this instance; skipping.';
      WHEN object_not_in_prerequisite_state THEN
        RAISE NOTICE 'pg_net schema change is not allowed in current environment; skipping.';
    END;
  END IF;
END
$$;
