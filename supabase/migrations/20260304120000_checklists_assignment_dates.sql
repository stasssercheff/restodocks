-- Настройки создания чеклиста: сотрудники, deadline, на когда
-- assigned_employee_ids: массив UUID сотрудников (null/пустой = всем)
-- deadline_at, scheduled_for_at: опциональные дата+время

ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_ids JSONB DEFAULT '[]';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS scheduled_for_at TIMESTAMP WITH TIME ZONE;

COMMENT ON COLUMN checklists.assigned_employee_ids IS 'Массив UUID сотрудников. null или [] = всем. Непустой = выбранным.';
COMMENT ON COLUMN checklists.deadline_at IS 'Срок выполнения (опционально).';
COMMENT ON COLUMN checklists.scheduled_for_at IS 'На когда назначен чеклист (опционально).';
