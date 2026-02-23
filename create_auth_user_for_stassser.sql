-- Создание Supabase Auth пользователя для stassser@gmail.com
-- и привязка к существующему employee

-- 1. Проверить текущего пользователя
SELECT 'Current stassser data:' as info;
SELECT id, full_name, email, auth_user_id, password_hash
FROM employees
WHERE email = 'stassser@gmail.com';

-- 2. Здесь нужно вручную создать пользователя в Supabase Auth:
-- В Dashboard → Authentication → Users → Add User
-- Email: stassser@gmail.com
-- Password: 1111!
-- Auto Confirm: ON

-- 3. После создания пользователя, получить его auth_user_id из Dashboard
-- и обновить запись в employees:

-- UPDATE employees
-- SET auth_user_id = 'полученный-из-dashboard-auth-user-id'
-- WHERE email = 'stassser@gmail.com';

-- 4. Проверить результат
SELECT 'After auth_user_id update:' as info;
SELECT id, full_name, email, auth_user_id
FROM employees
WHERE email = 'stassser@gmail.com';