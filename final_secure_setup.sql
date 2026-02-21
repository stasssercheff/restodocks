-- ФИНАЛЬНАЯ БЕЗОПАСНАЯ НАСТРОЙКА RLS

-- Включаем RLS
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Удаляем все старые политики
DROP POLICY IF EXISTS "employees_establishment_access" ON employees;
DROP POLICY IF EXISTS "employees_access_policy" ON employees;
DROP POLICY IF EXISTS "establishments_owner_access" ON establishments;
DROP POLICY IF EXISTS "establishments_access_policy" ON establishments;
DROP POLICY IF EXISTS "products_access" ON products;
DROP POLICY IF EXISTS "products_global_access" ON products;
DROP POLICY IF EXISTS "establishment_products_access" ON establishment_products;

-- Безопасные политики для авторизованных пользователей
CREATE POLICY "employees_secure" ON employees
FOR ALL USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
    OR id = auth.uid()
);

CREATE POLICY "establishments_secure" ON establishments
FOR ALL USING (id IN (
    SELECT establishment_id FROM employees
    WHERE id = auth.uid() AND 'owner' = ANY(roles)
));

CREATE POLICY "products_secure" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

CREATE POLICY "establishment_products_secure" ON establishment_products
FOR ALL USING (establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Анонимный доступ для регистрации
CREATE POLICY "anon_employees" ON employees FOR SELECT USING (true);
CREATE POLICY "anon_employees_insert" ON employees FOR INSERT WITH CHECK (true);
CREATE POLICY "anon_establishments" ON establishments FOR SELECT USING (true);
CREATE POLICY "anon_establishments_insert" ON establishments FOR INSERT WITH CHECK (true);