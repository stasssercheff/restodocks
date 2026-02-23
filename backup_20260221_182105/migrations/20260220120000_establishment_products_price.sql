-- Добавляем price и currency в establishment_products для хранения цен по заведениям
ALTER TABLE establishment_products ADD COLUMN IF NOT EXISTS price REAL;
ALTER TABLE establishment_products ADD COLUMN IF NOT EXISTS currency TEXT;

COMMENT ON COLUMN establishment_products.price IS 'Цена продукта в данном заведении';
COMMENT ON COLUMN establishment_products.currency IS 'Валюта (RUB, USD и т.д.)';
