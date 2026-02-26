-- Доступ к данным: при регистрации выключен. Включается руководителем в карточке сотрудника.
-- С выключенным доступом сотрудник видит только график.

ALTER TABLE employees ADD COLUMN IF NOT EXISTS data_access_enabled boolean DEFAULT false NOT NULL;
COMMENT ON COLUMN employees.data_access_enabled IS 'Доступ к данным (кроме графика). По умолчанию false при регистрации.';
