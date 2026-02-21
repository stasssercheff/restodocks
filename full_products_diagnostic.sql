-- ПОЛНАЯ ДИАГНОСТИКА ПРОБЛЕМЫ С ПРОДУКТАМИ
-- Выполнить в Supabase SQL Editor

-- 1. Проверяем текущее состояние RLS
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'products';

-- 2. Проверяем политики RLS для products
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'products';

-- 3. Проверяем количество записей в products без RLS
BEGIN;
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
SELECT 'Products in database (RLS disabled)' as check_name, COUNT(*) as count FROM products;
COMMIT;

-- 4. Проверяем establishment_products
SELECT
  'Establishment products total' as check_name,
  COUNT(*) as count
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 5. Проверяем соответствие
SELECT
  'Products in establishment_products' as check_name,
  COUNT(DISTINCT product_id) as count
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

SELECT
  'Products NOT in main table' as check_name,
  COUNT(*) as count
FROM (
  SELECT DISTINCT product_id
  FROM establishment_products
  WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
) ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE p.id IS NULL;

-- 6. Показываем примеры "сиротских" продуктов
SELECT
  ep.product_id,
  ep.price,
  ep.currency,
  'MISSING FROM PRODUCTS' as status
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE p.id IS NULL
  AND ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;