-- Повторное снятие лишних перегрузок `check_establishment_access`, если в проекте остался PostgREST 400 на /rpc/check_establishment_access
-- (дубли аргументов, кэш схемы). Идемпотентно; безопасно применять повторно.
-- См. также 20260620120000_check_establishment_access_postgrest_hardening.sql

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS rp
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'check_establishment_access'
      AND pg_get_function_identity_arguments(p.oid) IS DISTINCT FROM 'p_establishment_id uuid'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s', r.rp);
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_establishment_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_establishment_access(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.check_establishment_access(uuid) FROM PUBLIC;

NOTIFY pgrst, 'reload schema';
