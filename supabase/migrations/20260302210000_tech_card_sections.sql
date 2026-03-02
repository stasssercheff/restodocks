-- Добавляем колонку sections (JSONB массив цехов) в tech_cards
-- Заменяет старую колонку section (String, не сохранялась)
-- Пустой массив [] = "Скрыто" (видят только шеф/су-шеф)
-- ['all'] = все цеха
-- ['hot_kitchen', 'cold_kitchen'] = конкретные цеха

ALTER TABLE tech_cards
  ADD COLUMN IF NOT EXISTS sections JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Индекс для быстрой фильтрации по цеху
CREATE INDEX IF NOT EXISTS idx_tech_cards_sections
  ON tech_cards USING GIN (sections);
