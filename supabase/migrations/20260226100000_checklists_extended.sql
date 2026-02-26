-- Расширение checklists: additional_name, type, action_config
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS additional_name TEXT;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'tasks';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS action_config JSONB DEFAULT '{"has_numeric":false,"has_toggle":true}'::jsonb;

-- Расширение checklist_items: tech_card_id
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL;

-- Черновики заполнения чеклистов (localStorage + сервер каждые 15 сек)
CREATE TABLE IF NOT EXISTS checklist_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(checklist_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_checklist_drafts_checklist ON checklist_drafts(checklist_id);
CREATE INDEX IF NOT EXISTS idx_checklist_drafts_employee ON checklist_drafts(employee_id);
CREATE INDEX IF NOT EXISTS idx_checklist_drafts_updated ON checklist_drafts(updated_at DESC);

ALTER TABLE checklist_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_checklist_drafts" ON checklist_drafts;
CREATE POLICY "anon_checklist_drafts" ON checklist_drafts
  FOR ALL TO anon USING (true) WITH CHECK (true);

COMMENT ON TABLE checklist_drafts IS 'Черновики заполнения чеклистов - автосохранение в браузере и на сервер каждые 15 сек.';
