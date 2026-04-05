-- RPC с RETURNS void иногда даёт пустой ответ (204); клиент/прокси может вести себя нестабильно.
-- Явный JSON — предсказуемый ответ PostgREST.

DROP FUNCTION IF EXISTS public.admin_delete_establishment(uuid);

CREATE OR REPLACE FUNCTION public.admin_delete_establishment(p_establishment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._delete_establishment_cascade(p_establishment_id);
  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.admin_delete_establishment(uuid) IS
  'Удаление заведения (админка, service_role). Возвращает {"ok":true}.';

REVOKE ALL ON FUNCTION public.admin_delete_establishment(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_establishment(uuid) TO service_role;
