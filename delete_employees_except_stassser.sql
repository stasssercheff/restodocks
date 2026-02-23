-- Удаление всех сотрудников кроме stassser@gmail.com
-- Выполнить в Supabase Dashboard → SQL Editor

-- 1. Отвязываем заведения от владельцев, которых удалим
UPDATE establishments
SET owner_id = NULL
WHERE owner_id IN (
  SELECT id FROM employees WHERE email NOT ILIKE 'stassser@gmail.com'
);

-- 2. Удаляем сотрудников, кроме stassser@gmail.com
DELETE FROM employees
WHERE email NOT ILIKE 'stassser@gmail.com';

-- 3. Проверка: должно остаться только 1 запись
SELECT id, email, full_name, roles, establishment_id FROM employees;
