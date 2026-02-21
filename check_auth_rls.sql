-- ПРОВЕРКА RLS ПОЛИТИК ДЛЯ АВТОРИЗАЦИИ

-- 1. RLS политики для establishments
SELECT
    'establishments' as table_name,
    policyname,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'establishments';

-- 2. RLS политики для employees
SELECT
    'employees' as table_name,
    policyname,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'employees';

-- 3. Проверить текущего пользователя
SELECT auth.uid() as current_user;

-- 4. Проверить доступ к establishment
SELECT
    id,
    name,
    owner_id
FROM establishments
WHERE id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
);

-- 5. Проверить доступ к employee
SELECT
    id,
    email,
    establishment_id,
    roles
FROM employees
WHERE id = auth.uid();