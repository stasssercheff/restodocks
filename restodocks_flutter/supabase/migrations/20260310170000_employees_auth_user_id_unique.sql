-- UNIQUE на auth_user_id: один аккаунт Auth — один employee.
-- PostgreSQL: несколько NULL допустимы, дубли non-NULL — нет.
-- Перед применением проверить на дубли: SELECT auth_user_id, COUNT(*) FROM employees WHERE auth_user_id IS NOT NULL GROUP BY auth_user_id HAVING COUNT(*) > 1;
DROP INDEX IF EXISTS idx_employees_auth_user_id;
CREATE UNIQUE INDEX idx_employees_auth_user_id ON employees(auth_user_id) WHERE auth_user_id IS NOT NULL;
