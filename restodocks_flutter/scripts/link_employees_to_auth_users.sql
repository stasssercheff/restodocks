-- Привязать сотрудников без auth_user_id к существующим пользователям Auth (по email).
-- Выполнить в Supabase SQL Editor. Требует наличие колонки employees.auth_user_id.
--
-- 1. Проверка: кто без привязки
-- SELECT e.id, e.email, e.full_name, e.auth_user_id
-- FROM employees e
-- WHERE e.auth_user_id IS NULL AND e.is_active = true;

-- 2. Привязка по совпадению email
UPDATE employees e
SET auth_user_id = au.id
FROM auth.users au
WHERE e.auth_user_id IS NULL
  AND LOWER(TRIM(e.email)) = LOWER(au.email)
  AND e.is_active = true;
