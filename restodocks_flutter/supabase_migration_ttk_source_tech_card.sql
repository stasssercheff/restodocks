-- Ингредиент ТТК может быть из номенклатуры (product_id) ИЛИ из другой ТТК — полуфабрикат (source_tech_card_id).
-- Выполните в SQL Editor Supabase после tt_ingredients.

ALTER TABLE tt_ingredients
  ADD COLUMN IF NOT EXISTS source_tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source_tech_card_name TEXT;

CREATE INDEX IF NOT EXISTS idx_tt_ingredients_source_tech_card ON tt_ingredients(source_tech_card_id);

COMMENT ON COLUMN tt_ingredients.source_tech_card_id IS 'Когда задан: ингредиент — полуфабрикат из другой ТТК; product_id при этом NULL.';
COMMENT ON COLUMN tt_ingredients.source_tech_card_name IS 'Название ТТК-полуфабриката для отображения.';
