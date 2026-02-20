-- Сброс пароля для сотрудника Stassser@gmail.com
-- Новый пароль: 123456

-- Вставьте этот SQL в Supabase SQL Editor

UPDATE employees
SET password_hash = '$2b$12$dZKbGwbhkEGr1E46ysGHFewFYVf6LO9yVjbur1IsoR/wQvDnAQ5Pa'
WHERE email = 'Stassser@gmail.com';

-- Проверка
SELECT id, email, full_name FROM employees WHERE email = 'Stassser@gmail.com';