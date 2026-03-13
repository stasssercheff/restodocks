-- HACCP INSERT: разрешить created_by_employee_id для сотрудников с auth_user_id = auth.uid()
-- (app передаёт employees.id, но RLS ожидал auth.uid(); для PIN-сотрудников id != auth.uid())
-- Требует колонку employees.auth_user_id. Если 20260225180000 применена (auth_user_id удалена),
-- закомментировать вторую строку в UNION.

-- Расширить current_user_establishment_ids для сотрудников с auth_user_id
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

-- Обновить INSERT policies: created_by_employee_id IN current_user_employee_ids()
DROP POLICY IF EXISTS "auth_haccp_numeric_insert" ON haccp_numeric_logs;
CREATE POLICY "auth_haccp_numeric_insert" ON haccp_numeric_logs FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND created_by_employee_id IN (SELECT current_user_employee_ids())
    AND NOT is_current_user_view_only_owner()
  );

DROP POLICY IF EXISTS "auth_haccp_status_insert" ON haccp_status_logs;
CREATE POLICY "auth_haccp_status_insert" ON haccp_status_logs FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND created_by_employee_id IN (SELECT current_user_employee_ids())
    AND NOT is_current_user_view_only_owner()
  );

DROP POLICY IF EXISTS "auth_haccp_quality_insert" ON haccp_quality_logs;
CREATE POLICY "auth_haccp_quality_insert" ON haccp_quality_logs FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND created_by_employee_id IN (SELECT current_user_employee_ids())
    AND NOT is_current_user_view_only_owner()
  );
