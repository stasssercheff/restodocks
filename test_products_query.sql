-- ТЕСТ ЗАПРОСА ПРОДУКТОВ

-- Проверить текущего пользователя
SELECT auth.uid() as current_user_id;

-- Прямой запрос к products (должен работать с RLS)
SELECT COUNT(*) as products_via_select FROM products;

-- Запрос с лимитом
SELECT id, name, category, base_price, currency
FROM products
ORDER BY name
LIMIT 3;

-- Проверить, работает ли RLS
SELECT
    schemaname,
    tablename,
    policyname,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'products';