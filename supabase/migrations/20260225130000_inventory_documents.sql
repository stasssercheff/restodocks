-- Таблица документов инвентаризации: сохранённые бланки для кабинета шеф-повара и входящих.
-- payload: { header: {...}, rows: [...], aggregatedProducts: [...] }
CREATE TABLE IF NOT EXISTS inventory_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_email TEXT NOT NULL,
  payload JSONB NOT NULL,
  email_sent_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_documents_establishment ON inventory_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_documents_recipient ON inventory_documents(recipient_chef_id);
CREATE INDEX IF NOT EXISTS idx_inventory_documents_created_at ON inventory_documents(created_at DESC);

COMMENT ON TABLE inventory_documents IS 'Документы инвентаризации: бланк после «Завершить» сохраняется во входящие шефу и собственнику.';

-- Anon-доступ (приложение использует custom auth через employees)
ALTER TABLE inventory_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_inventory_documents_select" ON inventory_documents;
CREATE POLICY "anon_inventory_documents_select" ON inventory_documents
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "anon_inventory_documents_insert" ON inventory_documents
  FOR INSERT TO anon WITH CHECK (true);
