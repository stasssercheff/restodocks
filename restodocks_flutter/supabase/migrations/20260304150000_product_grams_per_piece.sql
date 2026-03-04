-- Вес 1 шт (граммы) — для продуктов с unit=шт, аналог package_weight_grams для упаковки
ALTER TABLE products ADD COLUMN IF NOT EXISTS grams_per_piece REAL;
COMMENT ON COLUMN products.grams_per_piece IS 'Вес одной штуки в граммах (для unit=шт/pcs)';
