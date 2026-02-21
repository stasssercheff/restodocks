-- ПРОВЕРКА ТЕКУЩЕГО СОСТОЯНИЯ RLS ПОЛИТИК
-- Выполнить в Supabase SQL Editor

-- 1. Проверить, включен ли RLS на основных таблицах
SELECT
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('products', 'establishment_products', 'employees', 'establishments')
ORDER BY tablename;

-- 2. Посмотреть все текущие политики
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 3. Проверить данные в products
SELECT COUNT(*) as products_count FROM products;

-- 4. Проверить данные в establishment_products
SELECT
    establishment_id,
    COUNT(*) as products_count
FROM establishment_products
GROUP BY establishment_id;

-- 5. Проверить, можем ли мы прочитать продукты (тест запроса)
SELECT id, name, category, base_price, currency
FROM products
LIMIT 5;