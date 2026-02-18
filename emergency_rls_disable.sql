-- ЭКСТРЕННОЕ ОТКЛЮЧЕНИЕ RLS ДЛЯ establishment_products
-- Выполнить ТОЛЬКО для диагностики проблемы 400!

ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;

-- Проверяем статус
SELECT schemaname, tablename, rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'establishment_products';