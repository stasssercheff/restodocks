-- Фото профиля сотрудника
ALTER TABLE employees ADD COLUMN IF NOT EXISTS avatar_url TEXT;
COMMENT ON COLUMN employees.avatar_url IS 'URL фото в Supabase Storage (bucket avatars)';

-- ВАЖНО: Создайте bucket "avatars" в Supabase Dashboard: Storage → New bucket → имя "avatars" → Public bucket
