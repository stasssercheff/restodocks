-- ЭКСТРЕННОЕ ОТКЛЮЧЕНИЕ RLS - ВЕРНУТЬ ДОСТУП К СИСТЕМЕ

-- Отключаем RLS на всех основных таблицах
ALTER TABLE employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE establishments DISABLE ROW LEVEL SECURITY;
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;

-- Удаляем все сломанные политики
DROP POLICY IF EXISTS "employees_access_policy" ON employees;
DROP POLICY IF EXISTS "establishments_access_policy" ON establishments;
DROP POLICY IF EXISTS "products_access" ON products;
DROP POLICY IF EXISTS "establishment_products_access" ON establishment_products;

-- Проверяем, что всё отключено
SELECT
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('employees', 'establishments', 'products', 'establishment_products')
ORDER BY tablename;