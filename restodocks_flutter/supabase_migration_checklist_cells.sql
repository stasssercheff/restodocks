-- Расширение checklist_items: типы ячеек и опции выпадающих списков.
-- Выполните в SQL Editor Supabase после supabase_migration_checklists.sql.

-- Добавить колонки в checklist_items
ALTER TABLE checklist_items
  ADD COLUMN IF NOT EXISTS cell_type TEXT NOT NULL DEFAULT 'checkbox',
  ADD COLUMN IF NOT EXISTS dropdown_options JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN checklist_items.cell_type IS 'Тип ячейки: quantity, checkbox, dropdown';
COMMENT ON COLUMN checklist_items.dropdown_options IS 'Опции для выпадающего списка (массив строк)';

-- Таблица отправленных заполненных чеклистов (входящие шеф-повара)
CREATE TABLE IF NOT EXISTS checklist_submissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  filled_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checklist_submissions_establishment ON checklist_submissions(establishment_id);
CREATE INDEX IF NOT EXISTS idx_checklist_submissions_recipient ON checklist_submissions(recipient_chef_id);
CREATE INDEX IF NOT EXISTS idx_checklist_submissions_created_at ON checklist_submissions(created_at DESC);

COMMENT ON TABLE checklist_submissions IS 'Отправленные заполненные чеклисты: входящие шеф-повара.';
