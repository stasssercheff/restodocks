-- Документация заведения: название, тема, видимость (подразделение/цех/сотрудник), текст.
-- Владелец и менеджмент: создание, редактирование, просмотр. Остальные: только просмотр.

CREATE TABLE IF NOT EXISTS establishment_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by UUID REFERENCES employees(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  topic TEXT,
  visibility_type TEXT NOT NULL DEFAULT 'all', -- 'all' | 'department' | 'section' | 'employee'
  visibility_ids JSONB DEFAULT '[]'::jsonb,
  body TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_establishment_documents_establishment ON establishment_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_establishment_documents_updated ON establishment_documents(updated_at DESC);

ALTER TABLE establishment_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_establishment_documents" ON establishment_documents;
CREATE POLICY "anon_establishment_documents" ON establishment_documents FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_establishment_documents" ON establishment_documents;
CREATE POLICY "auth_establishment_documents" ON establishment_documents FOR ALL TO authenticated USING (true) WITH CHECK (true);

COMMENT ON TABLE establishment_documents IS 'Документация заведения. Видимость: all, department (kitchen/bar/hall/management), section (цех), employee (список id).';
