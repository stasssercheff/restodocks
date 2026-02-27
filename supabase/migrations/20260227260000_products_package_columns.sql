-- Добавляем колонки package_price и package_weight_grams в таблицу products
ALTER TABLE products ADD COLUMN IF NOT EXISTS package_price REAL;
ALTER TABLE products ADD COLUMN IF NOT EXISTS package_weight_grams REAL;

COMMENT ON COLUMN products.package_price IS 'Цена за одну упаковку';
COMMENT ON COLUMN products.package_weight_grams IS 'Вес упаковки в граммах';
