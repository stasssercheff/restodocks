-- Диагностика и исправление: auth user есть, employee нет (после подтверждения email не можем войти)
-- Выполнить в Supabase Dashboard → SQL Editor

-- 1. Проверка: какие auth пользователи БЕЗ записи в employees
SELECT au.id, au.email, au.email_confirmed_at, au.created_at
FROM auth.users au
LEFT JOIN employees e ON e.id = au.id
WHERE e.id IS NULL;

-- 2. Заведения без владельца (owner_id = null)
SELECT id, name, created_at FROM establishments WHERE owner_id IS NULL;

-- 3. ЕСЛИ есть 1 auth user без employee И 1 establishment без owner:
--    Вручную создайте employee (подставьте свои данные):
/*
INSERT INTO employees (id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, created_at, updated_at)
SELECT 
  au.id,
  COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.email, '@', 1)),  -- имя из metadata или из email
  NULL,
  au.email,
  NULL,
  'management',
  NULL,
  ARRAY['owner'],
  (SELECT id FROM establishments WHERE owner_id IS NULL ORDER BY created_at DESC LIMIT 1),
  lpad((floor(random() * 900000) + 100000)::text, 6, '0'),
  'ru',
  true,
  now(),
  now()
FROM auth.users au
LEFT JOIN employees e ON e.id = au.id
WHERE e.id IS NULL
  AND au.email_confirmed_at IS NOT NULL
LIMIT 1;

UPDATE establishments SET owner_id = (SELECT id FROM auth.users WHERE email = 'ВАШ_EMAIL@example.com' LIMIT 1)
WHERE id = (SELECT establishment_id FROM employees WHERE email = 'ВАШ_EMAIL@example.com' LIMIT 1);
*/
