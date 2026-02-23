-- Очистка "застрявших" email адресов из базы данных Restodocks
-- Выполнять в Supabase SQL Editor
-- Это удалит незавершенные регистрации компаний + владельцев

-- 1. Удалить сотрудников с тестовыми email паттернами (кроме владельцев)
DELETE FROM employees
WHERE (email ILIKE '%test%' OR
       email ILIKE '%demo%' OR
       email ILIKE '%example%' OR
       email ILIKE '%temp%' OR
       email ILIKE '%fake%')
AND NOT (roles @> ARRAY['owner']);

-- 2. Удалить неактивных владельцев и их заведения
DELETE FROM establishments
WHERE owner_id IN (
  SELECT id FROM employees
  WHERE roles @> ARRAY['owner'] AND is_active = false
);

DELETE FROM employees
WHERE roles @> ARRAY['owner'] AND is_active = false;

-- 3. Удалить застрявших владельцев (без заведений)
DELETE FROM employees
WHERE roles @> ARRAY['owner']
AND id NOT IN (
  SELECT owner_id
  FROM establishments
  WHERE owner_id IS NOT NULL
);

-- 4. Удалить пустые заведения (без owner_id или без активных сотрудников)
DELETE FROM establishments
WHERE owner_id IS NULL
   OR owner_id NOT IN (SELECT id FROM employees WHERE roles @> ARRAY['owner'] AND is_active = true)
   OR id NOT IN (
     SELECT DISTINCT establishment_id
     FROM employees
     WHERE is_active = true
   );

-- 5. Проверить результат
SELECT
  (SELECT COUNT(*) FROM employees) as total_employees,
  (SELECT COUNT(*) FROM establishments) as total_establishments,
  (SELECT COUNT(*) FROM employees WHERE roles @> ARRAY['owner']) as owners_count;

-- 6. Показать оставшиеся email адреса (для проверки)
SELECT e.email, e.roles, e.is_active, est.name as establishment_name
FROM employees e
LEFT JOIN establishments est ON e.id = est.owner_id
ORDER BY e.created_at DESC;