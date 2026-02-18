-- Расширенная миграция для таблицы переводов v2
-- Добавляет поля для универсальной локализации

-- Создание таблицы если не существует
CREATE TABLE IF NOT EXISTS translations (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL, -- 'product', 'techCard', 'checklist', 'ui'
  entity_id TEXT NOT NULL, -- ID сущности
  field_name TEXT NOT NULL, -- название поля (name, description, etc.)
  source_text TEXT NOT NULL,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  translated_text TEXT NOT NULL,
  is_manual_override BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by TEXT,

  -- Уникальный индекс для предотвращения дубликатов
  UNIQUE(entity_type, entity_id, field_name, source_language, target_language)
);

-- Индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_translations_entity
ON translations(entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_translations_field
ON translations(field_name);

CREATE INDEX IF NOT EXISTS idx_translations_languages
ON translations(source_language, target_language);

CREATE INDEX IF NOT EXISTS idx_translations_manual_override
ON translations(is_manual_override) WHERE is_manual_override = true;

-- Индекс для полнотекстового поиска (если нужно)
CREATE INDEX IF NOT EXISTS idx_translations_source_text
ON translations USING gin(to_tsvector('english', source_text));

-- RLS политика
ALTER TABLE translations ENABLE ROW LEVEL SECURITY;

-- Политика: все могут читать переводы
CREATE POLICY "Translations are viewable by everyone"
ON translations FOR SELECT
USING (true);

-- Политика: только аутентифицированные пользователи могут создавать переводы
CREATE POLICY "Authenticated users can create translations"
ON translations FOR INSERT
WITH CHECK (auth.role() = 'authenticated');

-- Политика: пользователи могут обновлять только свои manual overrides
CREATE POLICY "Users can update their manual overrides"
ON translations FOR UPDATE
USING (
  is_manual_override = true AND
  created_by = auth.uid()::text
);

-- Комментарии
COMMENT ON TABLE translations IS 'Универсальная таблица переводов для продуктов, ТТК, чек-листов и UI';
COMMENT ON COLUMN translations.entity_type IS 'Тип сущности: product, techCard, checklist, ui';
COMMENT ON COLUMN translations.entity_id IS 'ID сущности (UUID продукта, ТТК и т.д.)';
COMMENT ON COLUMN translations.field_name IS 'Название поля в сущности (name, description, etc.)';
COMMENT ON COLUMN translations.is_manual_override IS 'Флаг ручного перевода - защищает от автозамены';