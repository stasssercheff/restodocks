-- ФИНАЛЬНАЯ ПРОВЕРКА ДЕПЛОЯ И ИСПРАВЛЕНИЙ

-- 1. ПРОВЕРКА СТРУКТУРЫ establishment_products
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY column_name;

-- 2. ПРОВЕРКА ДАННЫХ
SELECT COUNT(*) as total_establishment_products FROM establishment_products;

-- 3. ПРОВЕРКА КОНКРЕТНОГО ЗАВЕДЕНИЯ
SELECT
  ep.*,
  p.name as product_name
FROM establishment_products ep
LEFT JOIN products p ON ep.product_id = p.id
WHERE ep.establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 5;

-- 4. ТЕСТ ЗАПРОСА ИЗ КОДА
SELECT product_id, price, currency
FROM establishment_products
WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'
LIMIT 3;

-- 5. ПРОВЕРКА RLS ПОЛИТИК
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'establishment_products';

-- 6. ПРОВЕРКА ПРОДУКТОВ
SELECT COUNT(*) as total_products FROM products;

-- 7. ПРОВЕРКА ТТК
SELECT COUNT(*) as total_ttk FROM tech_cards;