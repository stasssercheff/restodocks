-- Добавить assigned_department в checklists для разделения по подразделениям (кухня, бар, зал)
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_department TEXT DEFAULT 'kitchen';

COMMENT ON COLUMN checklists.assigned_department IS 'Подразделение: kitchen, bar, hall. По умолчанию kitchen.';
