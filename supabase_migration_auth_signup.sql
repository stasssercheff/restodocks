-- Политики для регистрации (signup) через Supabase Auth
-- Позволяет новым пользователям создавать establishment и employee

-- Establishments: разрешить INSERT нового заведения с owner_id = auth.uid()
DROP POLICY IF EXISTS "establishments_insert_owner" ON establishments;
CREATE POLICY "establishments_insert_owner" ON establishments
FOR INSERT WITH CHECK (owner_id = auth.uid());

-- Employees: разрешить INSERT своей записи (id = auth.uid())
DROP POLICY IF EXISTS "employees_insert_self" ON employees;
CREATE POLICY "employees_insert_self" ON employees
FOR INSERT WITH CHECK (id = auth.uid());

-- Employees: разрешить INSERT для владельца (добавление сотрудников в своё заведение)
DROP POLICY IF EXISTS "employees_insert_owner" ON employees;
CREATE POLICY "employees_insert_owner" ON employees
FOR INSERT WITH CHECK (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);
