-- ИСПРАВЛЕНИЕ RLS ПОЛИТИК v2

-- Удаляем все существующие политики
DROP POLICY IF EXISTS "Users can view establishment products" ON establishment_products;
DROP POLICY IF EXISTS "Users can manage establishment products" ON establishment_products;
DROP POLICY IF EXISTS "Users can view establishment products from their establishment" ON establishment_products;
DROP POLICY IF EXISTS "Users can manage establishment products from their establishment" ON establishment_products;

-- Включаем RLS
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Создаем простые и понятные политики
-- 1. Просмотр: пользователь может видеть продукты своего заведения
CREATE POLICY "allow_select_own_establishment_products" ON establishment_products
FOR SELECT USING (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
);

-- 2. Вставка: пользователь может добавлять продукты в свое заведение
CREATE POLICY "allow_insert_own_establishment_products" ON establishment_products
FOR INSERT WITH CHECK (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
);

-- 3. Обновление: пользователь может обновлять продукты своего заведения
CREATE POLICY "allow_update_own_establishment_products" ON establishment_products
FOR UPDATE USING (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
) WITH CHECK (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
);

-- 4. Удаление: пользователь может удалять продукты своего заведения
CREATE POLICY "allow_delete_own_establishment_products" ON establishment_products
FOR DELETE USING (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
);

-- Проверяем созданные политики
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'establishment_products';