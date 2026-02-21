-- ПРОВЕРКА ПУСТОТЫ ТАБЛИЦЫ PRODUCTS

-- 1. Сколько продуктов в products
SELECT COUNT(*) as products_count FROM products;

-- 2. Сколько записей в establishment_products для этого заведения
SELECT COUNT(*) as nomenclature_count
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 3. Показать первые 5 записей из establishment_products
SELECT product_id, price, currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;

-- 4. Проверить, существуют ли эти product_id в products
SELECT
    ep.product_id,
    CASE WHEN p.id IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END as status_in_products,
    p.name as product_name
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 10;

-- 5. Общий подсчет
SELECT
    COUNT(*) as total_nomenclature_entries,
    COUNT(CASE WHEN p.id IS NOT NULL THEN 1 END) as products_that_exist,
    COUNT(CASE WHEN p.id IS NULL THEN 1 END) as products_missing_from_products_table
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';