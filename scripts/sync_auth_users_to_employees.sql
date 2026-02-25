-- Синхронизация: добавить в employees всех из auth.users, у кого ещё нет записи.
-- Запустить в Supabase SQL Editor.

-- 1. Проверка: кто в Auth и кого нет в employees
SELECT au.id, au.email,
  EXISTS (SELECT 1 FROM employees e WHERE e.auth_user_id = au.id) as has_employee_by_auth,
  EXISTS (SELECT 1 FROM employees e WHERE LOWER(TRIM(e.email)) = LOWER(au.email)) as has_employee_by_email
FROM auth.users au;

-- 2. Вставка (establishment_id — у rebrikov или первое заведение)
INSERT INTO employees (
  id, email, full_name, password_hash, establishment_id,
  department, roles, is_active, auth_user_id, created_at, updated_at
)
SELECT 
  gen_random_uuid(),
  au.email,
  COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.email, '@', 1)),
  NULL,
  COALESCE(
    (SELECT establishment_id FROM employees WHERE email = 'rebrikov.st@gmail.com' LIMIT 1),
    (SELECT id FROM establishments LIMIT 1)
  ),
  'general',
  ARRAY['staff']::text[],
  true,
  au.id,
  now(),
  now()
FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM employees e 
  WHERE e.auth_user_id = au.id OR LOWER(TRIM(e.email)) = LOWER(au.email)
);
