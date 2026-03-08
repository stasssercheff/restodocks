-- Описание и состав для зала: показываются в меню зала вместо полной ТТК кухни.

ALTER TABLE tech_cards
  ADD COLUMN IF NOT EXISTS description_for_hall TEXT,
  ADD COLUMN IF NOT EXISTS composition_for_hall TEXT;

COMMENT ON COLUMN tech_cards.description_for_hall IS 'Описание блюда для гостей (меню зала)';
COMMENT ON COLUMN tech_cards.composition_for_hall IS 'Состав блюда для гостей (меню зала)';
