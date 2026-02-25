-- Фото блюд/ПФ в ТТК: блюдо — 1 фото, ПФ — до 10 фото (сетка).
-- Хранятся в Supabase Storage, bucket: tech_card_photos (создать вручную, public).

ALTER TABLE tech_cards
  ADD COLUMN IF NOT EXISTS photo_urls JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN tech_cards.photo_urls IS 'URL фото в Storage (bucket tech_card_photos). Блюдо: 1 элемент, ПФ: до 10.';
