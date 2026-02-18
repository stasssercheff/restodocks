-- ДИАГНОСТИКА ПРОБЛЕМЫ establishment_products 400

-- 1. ПРОВЕРКА АУТЕНТИФИКАЦИИ
SELECT
  auth.uid() as current_user_id,
  auth.jwt() ->> 'role' as user_role,
  auth.jwt() -> 'user_metadata' ->> 'email' as user_email;

-- 2. ПРОВЕРКА ЗАВЕДЕНИЯ
SELECT
  id,
  name,
  owner_id,
  auth.uid() = owner_id as is_owner
FROM establishments
WHERE id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 3. ПРОВЕРКА RLS ПОЛИТИК
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'establishment_products';

-- 4. ПРОВЕРКА СТРУКТУРЫ ТАБЛИЦЫ
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;

-- 5. ПРОСТОЙ ЗАПРОС БЕЗ RLS (ВРЕМЕННО)
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;

SELECT
  ep.*,
  e.name as establishment_name
FROM establishment_products ep
JOIN establishments e ON ep.establishment_id = e.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;

-- ВКЛЮЧАЕМ RLS ОБРАТНО
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- 6. ТЕСТОВЫЙ ЗАПРОС С АУТЕНТИФИКАЦИЕЙ
SELECT
  product_id,
  price,
  currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';