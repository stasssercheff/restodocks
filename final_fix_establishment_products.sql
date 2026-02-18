-- ФИНАЛЬНОЕ ИСПРАВЛЕНИЕ ПРОБЛЕМЫ establishment_products

-- ШАГ 1: Проверяем структуру таблицы
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;

-- ШАГ 2: ДОБАВЛЯЕМ НЕДОСТАЮЩИЕ ПОЛЯ (если их нет)
ALTER TABLE establishment_products
ADD COLUMN IF NOT EXISTS price DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'RUB';

-- ШАГ 3: Проверяем после добавления
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;

-- ШАГ 4: ВРЕМЕННО ОТКЛЮЧАЕМ RLS ДЛЯ ТЕСТА
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;

-- ШАГ 5: ТЕСТИРУЕМ ЗАПРОС
SELECT
  product_id,
  price,
  currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;

-- ШАГ 6: ВКЛЮЧАЕМ RLS ОБРАТНО
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- ШАГ 7: Проверяем RLS политики
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'establishment_products';

-- ШАГ 8: ТЕСТИРУЕМ С RLS
SELECT
  product_id,
  price,
  currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;