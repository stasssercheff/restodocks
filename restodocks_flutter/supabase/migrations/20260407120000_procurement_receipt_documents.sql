-- Документы приёмки поставок (во входящие шефу и собственнику; связь с заказом опциональна).
-- Удаление строк при удалении заведения: ON DELETE CASCADE от establishments.
CREATE TABLE IF NOT EXISTS procurement_receipt_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID REFERENCES employees(id) ON DELETE CASCADE,
  recipient_email TEXT,
  source_order_document_id UUID REFERENCES order_documents(id) ON DELETE SET NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_procurement_receipt_establishment
  ON procurement_receipt_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_procurement_receipt_created_at
  ON procurement_receipt_documents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_procurement_receipt_source_order
  ON procurement_receipt_documents(source_order_document_id)
  WHERE source_order_document_id IS NOT NULL;

COMMENT ON TABLE procurement_receipt_documents IS 'Приёмка поставок: факт, цены; строки по получателям как у order_documents.';

ALTER TABLE procurement_receipt_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_procurement_receipt_select" ON procurement_receipt_documents;
CREATE POLICY "auth_procurement_receipt_select" ON procurement_receipt_documents
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "auth_procurement_receipt_insert" ON procurement_receipt_documents;
CREATE POLICY "auth_procurement_receipt_insert" ON procurement_receipt_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE procurement_receipt_documents;
  END IF;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
