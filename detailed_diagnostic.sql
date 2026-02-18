-- ПОДРОБНАЯ ДИАГНОСТИКА ПРОБЛЕМЫ

-- 1. Проверяем текущего пользователя
SELECT
  auth.uid() as current_user_id,
  auth.jwt() ->> 'role' as user_role,
  auth.jwt() -> 'user_metadata' ->> 'email' as user_email;

-- 2. Проверяем establishment
SELECT id, name, owner_id, created_at
FROM establishments
WHERE id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 3. Проверяем, является ли текущий пользователь владельцем
SELECT
  e.id,
  e.name,
  e.owner_id,
  auth.uid() = e.owner_id as is_owner,
  auth.uid() as current_user
FROM establishments e
WHERE e.id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 4. Проверяем данные в establishment_products
SELECT
  ep.*,
  e.name as establishment_name,
  e.owner_id
FROM establishment_products ep
JOIN establishments e ON ep.establishment_id = e.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;

-- 5. Проверяем RLS политики
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'establishment_products';

-- 6. Проверяем, есть ли данные вообще
SELECT COUNT(*) as total_products FROM establishment_products;