-- ДИАГНОСТИКА ПРОБЛЕМЫ ВХОДА

-- 1. Проверяем существующие данные
SELECT
    'Employees count' as check_type,
    COUNT(*) as count
FROM employees;

SELECT
    'Establishments count' as check_type,
    COUNT(*) as count
FROM establishments;

-- 2. Проверяем RLS статус
SELECT
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('employees', 'establishments');

-- 3. Проверяем политики
SELECT
    tablename,
    policyname,
    qual
FROM pg_policies
WHERE schemaname = 'public'
    AND tablename IN ('employees', 'establishments');

-- 4. ВРЕМЕННО отключаем RLS для диагностики
ALTER TABLE employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE establishments DISABLE ROW LEVEL SECURITY;

-- 5. Проверяем, можем ли читать данные без RLS
SELECT id, email, roles FROM employees LIMIT 3;
SELECT id, name FROM establishments LIMIT 3;