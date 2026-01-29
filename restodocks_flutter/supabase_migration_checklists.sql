-- Чеклисты-шаблоны: шеф может править и создавать по аналогии.
-- Выполните в SQL Editor Supabase.

CREATE TABLE IF NOT EXISTS checklists (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS checklist_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checklists_establishment ON checklists(establishment_id);
CREATE INDEX IF NOT EXISTS idx_checklist_items_checklist ON checklist_items(checklist_id);

COMMENT ON TABLE checklists IS 'Шаблоны чеклистов: шеф редактирует и создаёт по аналогии.';
COMMENT ON TABLE checklist_items IS 'Пункты чеклиста-шаблона.';
