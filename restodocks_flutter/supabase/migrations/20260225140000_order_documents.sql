-- Заказы продуктов во входящие (шефу и собственнику): история по датам.
-- payload: { header: { supplierName, employeeName, createdAt, orderForDate }, items: [{ productName, unit, quantity, pricePerUnit, lineTotal }], grandTotal }
CREATE TABLE IF NOT EXISTS order_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_documents_establishment ON order_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_order_documents_created_at ON order_documents(created_at DESC);

COMMENT ON TABLE order_documents IS 'Заказы продуктов: после сохранения с количествами попадают во Входящие шефу и собственнику.';
