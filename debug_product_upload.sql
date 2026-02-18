-- ОТЛАДКА ПРОБЛЕМЫ ЗАГРУЗКИ ПРОДУКТОВ

-- 1. ПРОВЕРКА СТРУКТУРЫ establishment_products
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY column_name;

-- 2. ПРОВЕРКА ДАННЫХ
SELECT COUNT(*) as establishment_products_count FROM establishment_products;

-- 3. ПРОВЕРКА КОНКРЕТНОГО ЗАВЕДЕНИЯ
SELECT
  ep.*,
  p.name as product_name
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;

-- 4. ТЕСТ ЗАПРОСА ИЗ КОДА
SELECT
  product_id,
  price,
  currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 5. ПРОВЕРКА ПРОДУКТОВ
SELECT COUNT(*) as products_count FROM products LIMIT 10;

-- 6. ПРОВЕРКА RLS ПОЛИТИК
SELECT
  schemaname,
  tablename,
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'establishment_products';

-- 7. ПРОВЕРКА ДОСТУПА ПОЛЬЗОВАТЕЛЯ
SELECT auth.uid() as user_id;

-- 8. ПРОВЕРКА ЗАВЕДЕНИЙ ПОЛЬЗОВАТЕЛЯ
SELECT
  id,
  name,
  owner_id,
  auth.uid() = owner_id as is_owner
FROM establishments
WHERE owner_id = auth.uid();