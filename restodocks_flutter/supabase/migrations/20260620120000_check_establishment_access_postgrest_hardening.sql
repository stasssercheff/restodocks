-- PostgREST: 400 на /rpc/check_establishment_access — часто лишняя перегрузка функции, кэш схемы или права.
-- Безопасно: удаляем только перегрузки с аргументами, отличными от (p_establishment_id uuid).

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
