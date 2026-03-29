-- Восстановить ветку employees.auth_user_id в current_user_establishment_ids / current_user_employee_ids.
-- Миграция 20260318100000 убрала её, предполагая что колонка удалена в 20260225180000; на реальных БД
-- auth_user_id по-прежнему используется (RPC создания сотрудников, политики в 20260401000300 и др.).
-- Если у сотрудника id <> auth.uid(), но auth_user_id = auth.uid(), без этой ветки RLS отклоняет
-- INSERT в establishment_haccp_config и другие tenant-таблицы (Postgrest 42501).

CREATE OR REPLACE FUNCTION public.current_user_establishment_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM establishments WHERE owner_id = auth.uid()
  UNION
  SELECT establishment_id FROM employees WHERE id = auth.uid()
  UNION
  SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_user_employee_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM employees WHERE id = auth.uid()
  UNION
  SELECT id FROM employees WHERE auth_user_id = auth.uid();
$$;
