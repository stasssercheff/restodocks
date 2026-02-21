-- ПРОВЕРКА СТАТУСА РЕГИСТРАЦИИ

-- 1. Проверить RLS статус на таблицах регистрации
SELECT
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('employees', 'establishments');

-- 2. Проверить политики для анонимного доступа (регистрация)
SELECT
    tablename,
    policyname,
    qual
FROM pg_policies
WHERE schemaname = 'public'
    AND tablename IN ('employees', 'establishments')
    AND policyname LIKE '%anon%';

-- 3. Попробовать создать тестовую запись (без коммита)
BEGIN;
    -- Тестовая вставка (будет отменена)
    INSERT INTO establishments (name, default_currency)
    VALUES ('Test Establishment', 'VND');

    INSERT INTO employees (email, password_hash, full_name, establishment_id, roles)
    VALUES ('test@example.com', 'test_hash', 'Test User', (SELECT id FROM establishments WHERE name = 'Test Establishment'), ARRAY['owner']);
ROLLBACK;

-- 4. Проверить, что вставка прошла без ошибок RLS
SELECT 'Registration test completed - check for RLS errors above' as status;