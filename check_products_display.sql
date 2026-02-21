-- ПРОВЕРКА ПОЧЕМУ НЕ ОТОБРАЖАЮТСЯ ПРОДУКТЫ

-- 1. Сколько продуктов в таблице products
SELECT COUNT(*) as total_products_in_products_table FROM products;

-- 2. Сколько записей в establishment_products
SELECT COUNT(*) as total_nomenclature_entries FROM establishment_products WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 3. Проверить, соответствуют ли product_id из establishment_products реальным продуктам
SELECT
    COUNT(*) as total_nomenclature,
    COUNT(CASE WHEN p.id IS NOT NULL THEN 1 END) as products_exist,
    COUNT(CASE WHEN p.id IS NULL THEN 1 END) as products_missing
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 4. Показать первые 5 продуктов из products
SELECT id, name, category, base_price, currency, created_at
FROM products
ORDER BY created_at DESC
LIMIT 5;

-- 5. Проверить RLS политику для products
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
    AND tablename = 'products';