-- Статус сотрудника: постоянный/временный. Для временных — период доступа (дата начала и конца).
-- После даты конца — доступ ограничен (только личный график).
ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_status TEXT DEFAULT 'permanent' NOT NULL;
COMMENT ON COLUMN employees.employment_status IS 'Статус: permanent — постоянный, temporary — временный';

ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_start_date DATE;
COMMENT ON COLUMN employees.employment_start_date IS 'Дата начала (для временных). Задаёт шеф/барменеджер/менеджер зала.';

ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_end_date DATE;
COMMENT ON COLUMN employees.employment_end_date IS 'Дата конца (для временных). После этой даты — только личный график.';
