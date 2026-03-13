-- Исправление: колонка employees.auth_user_id удалена в 20260225180000.
-- Функции current_user_establishment_ids и current_user_employee_ids из 20260318000000
-- ссылались на auth_user_id — при INSERT в журнал ХАССП возникала ошибка.
-- Убираем ветку с auth_user_id, оставляем только id = auth.uid().

CREATE OR REPLACE FUNCTION public.current_user_establishment_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM establishments WHERE owner_id = auth.uid()
  UNION
  SELECT establishment_id FROM employees WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_user_employee_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM employees WHERE id = auth.uid();
$$;
