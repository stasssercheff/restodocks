-- МИГРАЦИЯ: Разрешить анонимный доступ для custom auth (вход по email/паролю через employees)
-- Restodocks НЕ использует Supabase Auth — вход идёт через таблицу employees.
-- Без этих политик anon не может читать employees/establishments — логин и регистрация не работают.

-- establishments: anon может SELECT (для получения компании после входа) и INSERT (регистрация)
DROP POLICY IF EXISTS "anon_select_establishments" ON establishments;
CREATE POLICY "anon_select_establishments" ON establishments
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;
CREATE POLICY "anon_insert_establishments" ON establishments
  FOR INSERT TO anon WITH CHECK (true);

-- employees: anon может SELECT (поиск по email для входа) и INSERT (регистрация)
DROP POLICY IF EXISTS "anon_select_employees" ON employees;
CREATE POLICY "anon_select_employees" ON employees
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_employees" ON employees;
CREATE POLICY "anon_insert_employees" ON employees
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_employees" ON employees;
CREATE POLICY "anon_update_employees" ON employees
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
