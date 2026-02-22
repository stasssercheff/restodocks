-- Очистка тестовых данных из базы данных Restodocks
-- Выполнять в Supabase SQL Editor (https://supabase.com/dashboard/project/YOUR_PROJECT/sql)

-- 1. Удалить тестовые сотрудники (кроме владельцев)
DELETE FROM employees
WHERE (email ILIKE '%test%' OR
       email ILIKE '%demo%' OR
       email ILIKE '%example%' OR
       email ILIKE '%temp%' OR
       email ILIKE '%fake%' OR
       email ILIKE '%sample%')
AND NOT (roles @> ARRAY['owner']); -- Не удалять владельцев компаний

-- 2. Проверить что удалено
SELECT COUNT(*) as deleted_test_employees
FROM employees
WHERE email ILIKE '%test%' OR
      email ILIKE '%demo%' OR
      email ILIKE '%example%' OR
      email ILIKE '%temp%' OR
      email ILIKE '%fake%' OR
      email ILIKE '%sample%';

-- 3. Очистить пустые заведения (без активных сотрудников)
DELETE FROM establishments
WHERE id NOT IN (
  SELECT DISTINCT establishment_id
  FROM employees
  WHERE is_active = true
);

-- 4. Проверить результат
SELECT
  (SELECT COUNT(*) FROM employees) as total_employees,
  (SELECT COUNT(*) FROM establishments) as total_establishments,
  (SELECT COUNT(*) FROM employees WHERE roles @> ARRAY['owner']) as owners_count,
  (SELECT COUNT(*) FROM employees WHERE is_active = true) as active_employees;