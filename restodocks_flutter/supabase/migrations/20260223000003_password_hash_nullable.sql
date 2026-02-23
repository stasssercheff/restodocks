-- password_hash нужен только для legacy-учёток (без Supabase Auth)
-- Новые учётки: пароль только в auth.users
ALTER TABLE employees ALTER COLUMN password_hash DROP NOT NULL;

COMMENT ON COLUMN employees.password_hash IS 'NULL для учёток через Supabase Auth. BCrypt или plain для legacy.';
