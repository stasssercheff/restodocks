-- Таблица документов инвентаризации: сохранённые бланки для кабинета шеф-повара и отправки на email.
-- Выполните в SQL Editor Supabase.

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

COMMENT ON TABLE inventory_documents IS 'Документы инвентаризации: бланк после «Завершить» сохраняется, отправляется в кабинет шеф-повара и на его email.';

-- При использовании RLS добавьте политики (например, доступ по establishment_id / recipient_chef_id).
-- Если RLS выключен, этот шаг не нужен.
