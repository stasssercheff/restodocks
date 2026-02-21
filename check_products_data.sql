-- Проверяем данные в таблицах products и establishment_products

-- 1. Сколько продуктов в основной таблице
SELECT COUNT(*) as total_products FROM products;

-- 2. Сколько записей в establishment_products для этого заведения
SELECT COUNT(*) as establishment_products_count
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 3. Первые 5 записей из establishment_products
SELECT product_id, price, currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;

-- 4. Проверяем, существуют ли эти product_id в таблице products
SELECT ep.product_id,
       CASE WHEN p.id IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END as status,
       p.name as product_name
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 10;

-- 5. Общее количество "сиротских" записей
SELECT COUNT(*) as orphaned_establishment_products
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE p.id IS NULL
AND ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';