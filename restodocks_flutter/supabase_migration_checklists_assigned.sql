-- Добавить assigned_section, assigned_employee_id в checklists (если ещё нет).
-- Выполните в SQL Editor Supabase.

ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_section TEXT;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
