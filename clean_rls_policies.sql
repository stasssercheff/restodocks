-- ОЧИСТКА И ФИНАЛЬНАЯ НАСТРОЙКА RLS ПОЛИТИК

-- Удаляем ВСЕ политики для чистоты
DROP POLICY IF EXISTS "Anonymous can search employees by email" ON employees;
DROP POLICY IF EXISTS "anon_select_employees" ON employees;
DROP POLICY IF EXISTS "anon_insert_employees" ON employees;
DROP POLICY IF EXISTS "anon_update_employees" ON employees;
DROP POLICY IF EXISTS "anon_create_employees" ON employees;
DROP POLICY IF EXISTS "anon_search_employees" ON employees;
DROP POLICY IF EXISTS "employees_access_fixed" ON employees;

DROP POLICY IF EXISTS "Anonymous can search establishments by pin" ON establishments;
DROP POLICY IF EXISTS "anon_select_establishments" ON establishments;
DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;
DROP POLICY IF EXISTS "anon_create_establishments" ON establishments;
DROP POLICY IF EXISTS "establishments_access" ON establishments;

-- МИНИМАЛЬНЫЙ НАБОР РАБОЧИХ ПОЛИТИК

-- Employees: пользователь видит себя и коллег из своего заведения
CREATE POLICY "employees_final" ON employees
FOR ALL USING (
    id = auth.uid()
    OR establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
);

-- Establishments: владелец видит свое заведение
CREATE POLICY "establishments_final" ON establishments
FOR ALL USING (
    id IN (
        SELECT establishment_id FROM employees
        WHERE id = auth.uid() AND 'owner' = ANY(roles)
    )
);

-- Products: все авторизованные пользователи видят продукты
CREATE POLICY "products_final" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

-- Establishment products: сотрудники видят продукты своего заведения
CREATE POLICY "establishment_products_final" ON establishment_products
FOR ALL USING (
    establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
);

-- Анонимный доступ для регистрации
CREATE POLICY "anon_employees_final" ON employees
FOR SELECT USING (true);

CREATE POLICY "anon_employees_insert_final" ON employees
FOR INSERT WITH CHECK (true);

CREATE POLICY "anon_establishments_final" ON establishments
FOR SELECT USING (true);

CREATE POLICY "anon_establishments_insert_final" ON establishments
FOR INSERT WITH CHECK (true);

-- ПРОВЕРКА
SELECT
    tablename,
    policyname,
    LEFT(qual, 50) as qual_preview
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;