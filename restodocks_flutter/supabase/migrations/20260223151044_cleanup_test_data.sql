-- Очистка тестовых данных: оставляем только stassser@gmail.com
-- Выполняем безопасную очистку с сохранением целостности данных

-- 1. Обнуляем owner_id у заведений, чей владелец будет удалён
UPDATE establishments
SET owner_id = NULL
WHERE owner_id IN (
  SELECT id FROM employees WHERE LOWER(TRIM(email)) != 'stassser@gmail.com'
);

-- 2. Удаляем токены сброса пароля (если таблица есть)
DELETE FROM password_reset_tokens
WHERE employee_id IN (SELECT id FROM employees WHERE LOWER(TRIM(email)) != 'stassser@gmail.com');

-- 3. Удаляем всех сотрудников кроме stassser@gmail.com
DELETE FROM employees
WHERE LOWER(TRIM(email)) != 'stassser@gmail.com';