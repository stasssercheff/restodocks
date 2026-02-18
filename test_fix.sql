-- БЫСТРЫЙ ТЕСТ ИСПРАВЛЕНИЯ

-- 1. Проверяем, что поля добавлены
SELECT column_name FROM information_schema.columns
WHERE table_name = 'establishment_products'
AND column_name IN ('price', 'currency');

-- 2. Тестируем запрос
SELECT COUNT(*) as rows_found
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 3. Если строк 0, добавляем тестовую
INSERT INTO establishment_products (establishment_id, product_id, price, currency)
SELECT '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b', p.id, 100.00, 'RUB'
FROM products p
WHERE p.id IS NOT NULL
LIMIT 1
ON CONFLICT (establishment_id, product_id) DO NOTHING;

-- 4. Финальный тест
SELECT product_id, price, currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';