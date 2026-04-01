-- Вызывается клиентом перед UPDATE профиля, если миграция backfill ещё не накатана:
-- проставляет auth_user_id = auth.uid() для строки id = auth.uid().

CREATE OR REPLACE FUNCTION public.ensure_employee_auth_link()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  UPDATE public.employees
  SET auth_user_id = v_uid
  WHERE id = v_uid AND auth_user_id IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_employee_auth_link() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_employee_auth_link() TO authenticated;
