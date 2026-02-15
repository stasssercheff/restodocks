-- Единицы измерения и процент отхода в ТТК-ингредиентах
-- Выполните в Supabase → SQL Editor после tt_ingredients.

ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS unit TEXT DEFAULT 'g';
ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS primary_waste_pct REAL DEFAULT 0;
ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS grams_per_piece REAL;

COMMENT ON COLUMN tt_ingredients.unit IS 'Единица: г, кг, шт, lb, oz, мл, л, gal и др.';
COMMENT ON COLUMN tt_ingredients.primary_waste_pct IS 'Процент отхода при первичной обработке';
COMMENT ON COLUMN tt_ingredients.grams_per_piece IS 'Грамм на штуку (для unit=шт)';

ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS cooking_loss_pct_override REAL;
COMMENT ON COLUMN tt_ingredients.cooking_loss_pct_override IS 'Ручной % ужарки (если задан — вместо способа приготовления)';

ALTER TABLE tt_ingredients ADD COLUMN IF NOT EXISTS output_weight REAL DEFAULT 0;
COMMENT ON COLUMN tt_ingredients.output_weight IS 'Выходной вес после ужарки (готовый продукт)';
