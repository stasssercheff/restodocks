-- ОТЛАДКА ФОРМАТА ОТВЕТА ИЗ establishment_products

-- Проверяем, что возвращает запрос
SELECT
  jsonb_pretty(row_to_json(ep)) as json_format,
  ep.*
FROM establishment_products ep
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 3;

-- Проверяем типы данных в колонках
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'establishment_products';

-- Тестируем тот же запрос, что делает Flutter код
SELECT
  product_id,
  price,
  currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- Проверяем, есть ли данные вообще
SELECT COUNT(*) as total_rows FROM establishment_products;
SELECT COUNT(*) as rows_for_establishment
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';