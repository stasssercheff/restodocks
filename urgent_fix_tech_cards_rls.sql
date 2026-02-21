-- СРОЧНО: Исправляем RLS для tech_cards
-- Выполнить в Supabase SQL Editor

-- Удаляем старую политику
DROP POLICY IF EXISTS "tech_cards_establishment_access" ON tech_cards;

-- Создаем новую политику
CREATE POLICY "tech_cards_establishment_access" ON tech_cards
FOR ALL USING (
  establishment_id IN (
    SELECT e.establishment_id
    FROM employees e
    WHERE e.id = auth.uid()
  )
);

-- Удаляем старую политику для ингредиентов
DROP POLICY IF EXISTS "tt_ingredients_tech_card_access" ON tt_ingredients;

-- Создаем новую политику для ингредиентов
CREATE POLICY "tt_ingredients_tech_card_access" ON tt_ingredients
FOR ALL USING (
  tech_card_id IN (
    SELECT tc.id
    FROM tech_cards tc
    WHERE tc.establishment_id IN (
      SELECT e.establishment_id
      FROM employees e
      WHERE e.id = auth.uid()
    )
  )
);

-- Проверяем результат
SELECT
  schemaname,
  tablename,
  policyname,
  qual
FROM pg_policies
WHERE tablename IN ('tech_cards', 'tt_ingredients');