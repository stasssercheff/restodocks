-- Проверяем RLS на tech_cards
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'tech_cards';

-- Проверяем статус RLS на таблице
SELECT tablename, rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'tech_cards';

-- Проверяем связанные таблицы
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename IN ('tt_ingredients', 'cooking_processes', 'departments', 'reviews', 'roles', 'schedules')
ORDER BY tablename, policyname;