-- Разрешение сотруднику редактировать свой личный график (как шеф).
ALTER TABLE employees ADD COLUMN IF NOT EXISTS can_edit_own_schedule boolean DEFAULT false NOT NULL;
COMMENT ON COLUMN employees.can_edit_own_schedule IS 'Сотрудник может менять свой личный график';
