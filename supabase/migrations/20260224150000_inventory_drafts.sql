-- Таблица черновиков инвентаризации
CREATE TABLE IF NOT EXISTS inventory_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_drafts_establishment ON inventory_drafts(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_employee ON inventory_drafts(employee_id);
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_updated ON inventory_drafts(updated_at DESC);

ALTER TABLE inventory_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_inventory_drafts" ON inventory_drafts;
CREATE POLICY "anon_inventory_drafts" ON inventory_drafts
  FOR ALL TO anon USING (true) WITH CHECK (true);

COMMENT ON TABLE inventory_drafts IS 'Черновики инвентаризаций - автоматическое сохранение на сервер.';
