-- Anon-политики для регистрации (компания + владелец) без Supabase-сессии
DROP POLICY IF EXISTS "anon_select_establishments" ON establishments;
CREATE POLICY "anon_select_establishments" ON establishments
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;
CREATE POLICY "anon_insert_establishments" ON establishments
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_establishments" ON establishments;
CREATE POLICY "anon_update_establishments" ON establishments
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_select_employees" ON employees;
CREATE POLICY "anon_select_employees" ON employees
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_employees" ON employees;
CREATE POLICY "anon_insert_employees" ON employees
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_employees" ON employees;
CREATE POLICY "anon_update_employees" ON employees
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
