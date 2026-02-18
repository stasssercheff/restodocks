-- ВКЛЮЧЕНИЕ RLS ОБРАТНО после диагностики

-- Сначала проверяем, что работает без RLS
SELECT COUNT(*) as total_establishment_products
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- Включаем RLS обратно
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Проверяем статус
SELECT schemaname, tablename, rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'establishment_products';