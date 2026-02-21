-- ИСПРАВЛЕНИЕ RLS ПОЛИТИК ДЛЯ establishment_products

-- Сначала удаляем существующие политики
DROP POLICY IF EXISTS "Users can view establishment products from their establishment" ON establishment_products;
DROP POLICY IF EXISTS "Users can manage establishment products from their establishment" ON establishment_products;

-- Включаем RLS
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Создаем правильные политики
-- Политика для чтения
CREATE POLICY "Users can view establishment products from their establishment"
ON establishment_products FOR SELECT
USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- Политика для вставки/обновления/удаления
CREATE POLICY "Users can manage establishment products from their establishment"
ON establishment_products FOR ALL
USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
)
WITH CHECK (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- Проверяем созданные политики
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'establishment_products';