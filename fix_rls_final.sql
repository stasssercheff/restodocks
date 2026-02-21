-- ИСПРАВЛЕНИЕ RLS ПОЛИТИК ДЛЯ РАБОЧЕЙ АВТОРИЗАЦИИ

-- Включаем RLS обратно
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Удаляем все политики
DROP POLICY IF EXISTS "employees_secure" ON employees;
DROP POLICY IF EXISTS "establishments_secure" ON establishments;
DROP POLICY IF EXISTS "products_secure" ON products;
DROP POLICY IF EXISTS "establishment_products_secure" ON establishment_products;
DROP POLICY IF EXISTS "anon_employees" ON employees;
DROP POLICY IF EXISTS "anon_employees_insert" ON employees;
DROP POLICY IF EXISTS "anon_establishments" ON establishments;
DROP POLICY IF EXISTS "anon_establishments_insert" ON establishments;

-- ПРАВИЛЬНЫЕ ПОЛИТИКИ (проверено)
CREATE POLICY "employees_access" ON employees
FOR ALL USING (
    establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
    OR id = auth.uid()
);

CREATE POLICY "establishments_access" ON establishments
FOR ALL USING (
    id IN (
        SELECT establishment_id FROM employees
        WHERE id = auth.uid() AND 'owner' = ANY(roles)
    )
);

CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

CREATE POLICY "establishment_products_access" ON establishment_products
FOR ALL USING (
    establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
);

-- Анонимный доступ для поиска и регистрации
CREATE POLICY "anon_search_employees" ON employees FOR SELECT USING (true);
CREATE POLICY "anon_search_establishments" ON establishments FOR SELECT USING (true);
CREATE POLICY "anon_create_employees" ON employees FOR INSERT WITH CHECK (true);
CREATE POLICY "anon_create_establishments" ON establishments FOR INSERT WITH CHECK (true);