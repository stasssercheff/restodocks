-- ПРОВЕРКА ТЕКУЩИХ ДАННЫХ И СТРУКТУРЫ

-- 1. Структура таблицы establishment_products
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;

-- 2. Есть ли данные в таблице?
SELECT COUNT(*) as total_rows FROM establishment_products;

-- 3. Данные для конкретного establishment
SELECT
  ep.*,
  p.name as product_name
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 4. Тестовый запрос как в коде
SELECT
  product_id,
  price,
  currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b';

-- 5. Проверить RLS
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'establishment_products';