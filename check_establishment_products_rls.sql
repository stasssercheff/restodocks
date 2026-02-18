-- Проверка RLS статуса для establishment_products
SELECT schemaname, tablename, rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'establishment_products';

-- Проверка существующих политик
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'establishment_products';

-- Проверка структуры таблицы
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;

-- Тестовый запрос с текущим пользователем
SELECT auth.uid() as current_user_id;

-- Проверка establishments для текущего пользователя
SELECT id, name, owner_id FROM establishments WHERE owner_id = auth.uid();