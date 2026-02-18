-- ТЕСТИРОВАНИЕ ОБНОВЛЕННОЙ ТАБЛИЦЫ establishment_products

-- Проверяем структуру
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;

-- Тестируем запрос (должен работать)
SELECT
  ep.establishment_id,
  ep.product_id,
  ep.price,
  ep.currency,
  ep.added_at,
  p.name as product_name
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 10;

-- Проверяем, что RLS политики работают
SELECT
  COUNT(*) as total_products_with_prices
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
  AND price IS NOT NULL;

-- Тестовый INSERT (если нужно)
-- INSERT INTO establishment_products (establishment_id, product_id, price, currency)
-- VALUES ('35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b', 'some-product-id', 100.50, 'RUB')
-- ON CONFLICT (establishment_id, product_id) DO UPDATE SET price = EXCLUDED.price, currency = EXCLUDED.currency;