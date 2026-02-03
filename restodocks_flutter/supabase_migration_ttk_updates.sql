-- Продукт: процент отхода (централизованно в карточке)
ALTER TABLE products ADD COLUMN IF NOT EXISTS primary_waste_pct REAL DEFAULT 0;

-- ТТК: технология приготовления (многоязычный текст)
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS technology_localized JSONB;
