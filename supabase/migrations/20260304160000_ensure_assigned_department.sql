-- Обеспечить наличие assigned_department (если миграция 20260303120000 не применялась)
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_department TEXT DEFAULT 'kitchen';
COMMENT ON COLUMN checklists.assigned_department IS 'Подразделение: kitchen, bar, hall. По умолчанию kitchen.';
