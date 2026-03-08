-- Исправление ошибки: Could not find the 'grams_per_piece' column of 'products'
-- Выполните этот SQL в Supabase Dashboard → SQL Editor → New query

-- Вес 1 шт (граммы) — для продуктов с unit=шт
ALTER TABLE products ADD COLUMN IF NOT EXISTS grams_per_piece REAL;
COMMENT ON COLUMN products.grams_per_piece IS 'Вес одной штуки в граммах (для unit=шт/pcs)';
