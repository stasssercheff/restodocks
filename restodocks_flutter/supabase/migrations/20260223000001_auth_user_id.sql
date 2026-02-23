-- Связь employees с Supabase Auth (auth.users)
-- auth_user_id = auth.uid() для пользователей, зарегистрированных через Supabase Auth
ALTER TABLE employees ADD COLUMN IF NOT EXISTS auth_user_id UUID;
CREATE INDEX IF NOT EXISTS idx_employees_auth_user_id ON employees(auth_user_id);

COMMENT ON COLUMN employees.auth_user_id IS 'ID пользователя Supabase Auth (auth.users). NULL для старых учёток.';
