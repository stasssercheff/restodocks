-- Политики для пользователей с Supabase Auth (auth.uid() не null)
-- Позволяют authenticated пользователям работать со своими данными

-- employees: выборка по auth_user_id
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
CREATE POLICY "auth_select_employees" ON employees
  FOR SELECT TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR establishment_id IN (SELECT establishment_id FROM employees e2 WHERE e2.auth_user_id = auth.uid())
  );

-- employees: вставка (регистрация сотрудника с PIN) — только свой auth_user_id
DROP POLICY IF EXISTS "auth_insert_employees" ON employees;
CREATE POLICY "auth_insert_employees" ON employees
  FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = auth.uid());

-- employees: обновление своего профиля или привязка auth_user_id при регистрации владельца
DROP POLICY IF EXISTS "auth_update_employees" ON employees;
CREATE POLICY "auth_update_employees" ON employees
  FOR UPDATE TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR (auth_user_id IS NULL AND LOWER(email) = LOWER(auth.jwt()->>'email'))
  )
  WITH CHECK (true);

-- establishments: выборка — свои заведения
DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
CREATE POLICY "auth_select_establishments" ON establishments
  FOR SELECT TO authenticated
  USING (
    owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid())
    OR id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  );

-- establishments: обновление — своё заведение
DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
CREATE POLICY "auth_update_establishments" ON establishments
  FOR UPDATE TO authenticated
  USING (
    owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid())
    OR id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  )
  WITH CHECK (true);
