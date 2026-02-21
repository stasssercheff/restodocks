-- ПРОВЕРКА СТРУКТУРЫ ТАБЛИЦЫ establishment_products

-- Структура таблицы
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default,
  character_maximum_length,
  numeric_precision,
  numeric_scale
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;

-- Индексы
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'establishment_products';

-- Ограничения (constraints)
SELECT
  conname,
  contype,
  condef
FROM pg_constraint
WHERE conrelid = 'establishment_products'::regclass;

-- Проверим, есть ли данные в таблице
SELECT
  COUNT(*) as total_rows,
  COUNT(DISTINCT establishment_id) as unique_establishments,
  COUNT(DISTINCT product_id) as unique_products
FROM establishment_products;

-- Пример данных (если есть)
SELECT * FROM establishment_products LIMIT 5;

-- Проверим внешние ключи
SELECT
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'establishment_products';