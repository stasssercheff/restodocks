-- Привязать stassser@gmail.com к Supabase Auth
-- Выполнить ПОСЛЕ того, как добавили пользователя в Dashboard:
--   Authentication → Users → Add user → Email: stassser@gmail.com, Password: (ваш пароль)

-- Получить auth_user_id и привязать к employee:
UPDATE employees
SET auth_user_id = (SELECT id FROM auth.users WHERE LOWER(email) = 'stassser@gmail.com' LIMIT 1),
    password_hash = NULL
WHERE LOWER(TRIM(email)) = 'stassser@gmail.com';
