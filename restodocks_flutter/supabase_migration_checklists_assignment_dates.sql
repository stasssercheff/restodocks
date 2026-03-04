-- Настройки чеклиста: сотрудники, deadline, на когда.
-- Выполните в SQL Editor Supabase.

ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_ids JSONB DEFAULT '[]';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS scheduled_for_at TIMESTAMP WITH TIME ZONE;
