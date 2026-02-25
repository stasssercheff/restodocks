-- Добавление фамилии сотрудника
ALTER TABLE employees ADD COLUMN IF NOT EXISTS surname TEXT;

COMMENT ON COLUMN employees.surname IS 'Фамилия сотрудника (опционально)';