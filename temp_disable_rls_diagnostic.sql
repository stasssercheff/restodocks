-- ВРЕМЕННО отключаем RLS для диагностики
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;

-- Проверяем, что отключено
SELECT schemaname, tablename, rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'establishment_products';

-- Пробуем тот же запрос
SELECT product_id, price, currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- Включаем RLS обратно
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;