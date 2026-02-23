-- Таблица документов заказов продуктов: сохранённые заказы для кабинета шеф-повара.
-- Структура аналогична inventory_documents.

CREATE TABLE IF NOT EXISTS order_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_email TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_documents_establishment ON order_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_order_documents_recipient ON order_documents(recipient_chef_id);
CREATE INDEX IF NOT EXISTS idx_order_documents_created_at ON order_documents(created_at DESC);

COMMENT ON TABLE order_documents IS 'Документы заказов продуктов: сохранённые заказы для кабинета шеф-повара (Входящие).';
