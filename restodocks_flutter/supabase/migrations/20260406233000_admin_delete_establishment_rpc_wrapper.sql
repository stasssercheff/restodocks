-- PostgREST / Supabase: RPC к функциям с именем, начинающимся с «_», часто недоступен из API.
-- Обёртка для админки (service_role); внутри — тот же каскад.

CREATE OR REPLACE FUNCTION public.admin_delete_establishment(p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._delete_establishment_cascade(p_establishment_id);
END;
$$;

COMMENT ON FUNCTION public.admin_delete_establishment(uuid) IS
  'Удаление заведения и связанных данных (админка, service_role). Вызывает _delete_establishment_cascade.';

REVOKE ALL ON FUNCTION public.admin_delete_establishment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_establishment(uuid) TO service_role;
