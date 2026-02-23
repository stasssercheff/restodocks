-- Миграция для таблицы переводов
-- Создает таблицу translations для кеширования AI переводов

CREATE TABLE IF NOT EXISTS translations (
  id TEXT PRIMARY KEY,
  source_text TEXT NOT NULL,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  translated_text TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by TEXT,

  -- Индексы для быстрого поиска
  UNIQUE(source_text, source_language, target_language)
);

-- Индекс для поиска по языкам
CREATE INDEX IF NOT EXISTS idx_translations_languages
ON translations(source_language, target_language);

-- Индекс для поиска по тексту (для fuzzy поиска)
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

-- Комментарии
COMMENT ON TABLE translations IS 'Кеш переводов для многоязычной поддержки продуктов';
COMMENT ON COLUMN translations.source_text IS 'Оригинальный текст для перевода';
COMMENT ON COLUMN translations.source_language IS 'Язык оригинального текста (ru, en, de, fr, es)';
COMMENT ON COLUMN translations.target_language IS 'Целевой язык перевода';
COMMENT ON COLUMN translations.translated_text IS 'Переведенный текст';
COMMENT ON COLUMN translations.created_by IS 'ID пользователя, создавшего перевод (опционально)';