-- ВРЕМЕННО ОТКЛЮЧАЕМ RLS НА EMPLOYEES ДЛЯ ВХОДА

ALTER TABLE employees DISABLE ROW LEVEL SECURITY;

-- Проверяем что можем читать
SELECT COUNT(*) as employees_count FROM employees;