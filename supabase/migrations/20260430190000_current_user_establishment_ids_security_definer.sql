-- RLS на employees использует current_user_establishment_ids(). Сама функция при
-- SECURITY INVOKER читает employees → снова RLS → рекурсия → Postgres 500.
-- DEFINER + search_path: считаем tenant без повторного входа в RLS на employees.

CREATE OR REPLACE FUNCTION public.current_user_establishment_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.establishments WHERE owner_id = auth.uid()
  UNION
  SELECT establishment_id FROM public.employees WHERE id = auth.uid()
  UNION
  SELECT establishment_id FROM public.employees WHERE auth_user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_user_employee_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.employees WHERE id = auth.uid()
  UNION
  SELECT id FROM public.employees WHERE auth_user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_user_establishment_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_establishment_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_establishment_ids() TO service_role;

REVOKE ALL ON FUNCTION public.current_user_employee_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_employee_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_employee_ids() TO service_role;
