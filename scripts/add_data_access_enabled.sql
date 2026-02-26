-- Колонка «Доступ к данным» в таблице employees
-- Нужна для переключателя «Доступ к данным» в карточке сотрудника (Сотрудники → редактирование).
-- Выполнить в Supabase Dashboard → SQL Editor → New query → вставить и Run.

ALTER TABLE employees ADD COLUMN IF NOT EXISTS data_access_enabled boolean DEFAULT false NOT NULL;
COMMENT ON COLUMN employees.data_access_enabled IS 'Доступ к данным (кроме графика). По умолчанию false при регистрации.';
