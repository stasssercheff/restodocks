-- ДОБАВЛЕНИЕ ПОЛЕЙ price И currency В establishment_products
-- Эти поля нужны для хранения индивидуальных цен заведения на продукты

-- Добавляем поля
ALTER TABLE establishment_products
ADD COLUMN IF NOT EXISTS price DECIMAL(10,2),
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'RUB';

-- Создаем индекс для поиска по цене
CREATE INDEX IF NOT EXISTS idx_establishment_products_price
  ON establishment_products(price)
  WHERE price IS NOT NULL;

-- Обновляем комментарий
COMMENT ON TABLE establishment_products IS 'Номенклатура: продукты заведения с индивидуальными ценами';

-- Проверяем структуру после изменений
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'establishment_products'
ORDER BY ordinal_position;