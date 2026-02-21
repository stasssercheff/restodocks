-- Добавление недостающих колонок в таблицу employees
-- Выполнить в Supabase SQL Editor

-- Предпочитаемый язык пользователя
ALTER TABLE employees
ADD COLUMN IF NOT EXISTS preferred_language TEXT DEFAULT 'ru'
CHECK (preferred_language IN ('ru', 'en', 'de', 'fr', 'es'));

-- URL аватара
ALTER TABLE employees
ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- Комментарии
COMMENT ON COLUMN employees.preferred_language IS 'Предпочитаемый язык интерфейса: ru, en, de, fr, es';
COMMENT ON COLUMN employees.avatar_url IS 'URL фото в Supabase Storage (bucket avatars)';

-- Индексы
CREATE INDEX IF NOT EXISTS idx_employees_preferred_language
ON employees(preferred_language);