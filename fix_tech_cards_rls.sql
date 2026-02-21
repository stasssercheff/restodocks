-- Исправляем RLS для tech_cards и связанных таблиц
-- На основе текущих политик из предыдущего дампа

-- Сначала проверяем текущие политики
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
WHERE tablename IN ('tech_cards', 'tt_ingredients', 'cooking_processes', 'departments', 'reviews', 'roles', 'schedules')
ORDER BY tablename, policyname;

-- Удаляем существующие политики для tech_cards
DROP POLICY IF EXISTS "tech_cards_establishment_access" ON tech_cards;

-- Создаем новую политику для tech_cards
CREATE POLICY "tech_cards_establishment_access"
ON tech_cards
FOR ALL
USING (
    establishment_id IN (
        SELECT establishments.id
        FROM establishments
        WHERE establishments.id IN (
            SELECT employees.establishment_id
            FROM employees
            WHERE employees.id = auth.uid()
        )
    )
);

-- Удаляем существующие политики для tt_ingredients
DROP POLICY IF EXISTS "tt_ingredients_tech_card_access" ON tt_ingredients;

-- Создаем новую политику для tt_ingredients
CREATE POLICY "tt_ingredients_tech_card_access"
ON tt_ingredients
FOR ALL
USING (
    tech_card_id IN (
        SELECT tech_cards.id
        FROM tech_cards
        WHERE tech_cards.establishment_id IN (
            SELECT establishments.id
            FROM establishments
            WHERE establishments.id IN (
                SELECT employees.establishment_id
                FROM employees
                WHERE employees.id = auth.uid()
            )
        )
    )
);

-- Проверяем статус RLS на всех таблицах
SELECT
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('tech_cards', 'tt_ingredients', 'cooking_processes', 'departments', 'reviews', 'roles', 'schedules')
ORDER BY tablename;