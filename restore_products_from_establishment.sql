-- ВОССТАНАВЛИВАЕМ ПРОДУКТЫ ИЗ ESTABLISHMENT_PRODUCTS
-- Выполнить после отключения RLS на products

-- 1. Создаем временную таблицу с уникальными product_id из establishment_products
CREATE TEMP TABLE temp_product_ids AS
SELECT DISTINCT
  ep.product_id,
  ep.price,
  ep.currency
FROM establishment_products ep
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
  AND ep.product_id NOT IN (SELECT id FROM products);

-- 2. Создаем продукты-заглушки на основе данных из establishment_products
INSERT INTO products (
  id,
  name,
  category,
  base_price,
  currency,
  unit,
  created_at,
  updated_at
)
SELECT
  t.product_id as id,
  'Product ' || substr(t.product_id, 1, 8) as name, -- Временное имя
  'unknown' as category,
  t.price,
  COALESCE(t.currency, 'VND') as currency,
  'г' as unit,
  NOW() as created_at,
  NOW() as updated_at
FROM temp_product_ids t;

-- 3. Проверяем результат
SELECT
  'Products created' as action,
  COUNT(*) as count
FROM products p
WHERE p.id IN (SELECT product_id FROM temp_product_ids);

-- 4. Включаем RLS обратно
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- 5. Проверяем, что политика работает
CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);