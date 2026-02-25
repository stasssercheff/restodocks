-- ДИАГНОСТИКА ВХОДА (Supabase SQL Editor)
-- Запустите в Supabase Dashboard > SQL Editor
-- Помогает найти причину «Неверный email или пароль»

-- 1. Проверка RLS на employees
SELECT 
  schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies 
WHERE tablename = 'employees';

-- 2. Сотрудники с email (без пароля в выводе)
SELECT id, email, is_active, 
       CASE WHEN password_hash IS NULL THEN 'NULL' 
            WHEN password_hash = '' THEN 'empty' 
            WHEN password_hash LIKE '$2%' THEN 'BCrypt' 
            ELSE 'plain' END as hash_type,
       auth_user_id IS NOT NULL as has_auth
FROM employees 
WHERE is_active = true 
ORDER BY email;

-- 3. Проверка anon доступа (должна быть политика для SELECT)
SELECT policyname, cmd 
FROM pg_policies 
WHERE tablename = 'employees' AND 'anon' = ANY(roles);

-- 4. auth.users (если сотрудник через Supabase Auth)
-- SELECT id, email, email_confirmed_at FROM auth.users LIMIT 5;
