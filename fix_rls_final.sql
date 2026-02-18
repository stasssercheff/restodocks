-- ОКОНЧАТЕЛЬНОЕ ИСПРАВЛЕНИЕ RLS ПОЛИТИК ДЛЯ establishment_products

-- УДАЛЯЕМ ВСЕ СУЩЕСТВУЮЩИЕ ПОЛИТИКИ
DROP POLICY IF EXISTS "Users can view establishment products" ON establishment_products;
DROP POLICY IF EXISTS "Users can manage establishment products" ON establishment_products;
DROP POLICY IF EXISTS "Users can view establishment products from their establishment" ON establishment_products;
DROP POLICY IF EXISTS "Users can manage establishment products from their establishment" ON establishment_products;
DROP POLICY IF EXISTS "allow_select_own_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "allow_insert_own_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "allow_update_own_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "allow_delete_own_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "allow_all_own_establishment_products" ON establishment_products;

-- ВКЛЮЧАЕМ RLS
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- ПРОСТЫЕ И НАДЕЖНЫЕ ПОЛИТИКИ
-- 1. ЧТЕНИЕ: пользователь может видеть продукты своих заведений
CREATE POLICY "read_own_establishment_products" ON establishment_products
FOR SELECT USING (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
);

-- 2. ВСТАВКА: пользователь может добавлять продукты в свои заведения
CREATE POLICY "insert_own_establishment_products" ON establishment_products
FOR INSERT WITH CHECK (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
);

-- 3. ОБНОВЛЕНИЕ: пользователь может обновлять продукты своих заведений
CREATE POLICY "update_own_establishment_products" ON establishment_products
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

-- 4. УДАЛЕНИЕ: пользователь может удалять продукты своих заведений
CREATE POLICY "delete_own_establishment_products" ON establishment_products
FOR DELETE USING (
  establishment_id IN (
    SELECT id FROM establishments
    WHERE owner_id = auth.uid()
  )
);

-- ПРОВЕРЯЕМ СОЗДАННЫЕ ПОЛИТИКИ
SELECT
  schemaname,
  tablename,
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'establishment_products';

-- ТЕСТИРУЕМ ЗАПРОС (ДОЛЖЕН РАБОТАТЬ)
SELECT
  COUNT(*) as product_count
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';