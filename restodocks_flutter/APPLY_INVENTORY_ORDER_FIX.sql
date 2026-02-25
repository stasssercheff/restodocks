-- Создание таблицы inventory_documents и политик RLS (если ещё не применено через миграции)
-- Выполнить в Supabase SQL Editor, если инвентаризация и заказы не попадают во входящие

-- 1. Таблица inventory_documents
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

-- Политики anon для custom auth (приложение не использует Supabase Auth для части пользователей)
ALTER TABLE inventory_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_inventory_documents_select" ON inventory_documents;
CREATE POLICY "anon_inventory_documents_select" ON inventory_documents
  FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "anon_inventory_documents_insert" ON inventory_documents
  FOR INSERT TO anon WITH CHECK (true);

-- 2. Политики для order_documents (таблица должна уже существовать)
ALTER TABLE order_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_order_documents_select" ON order_documents;
CREATE POLICY "anon_order_documents_select" ON order_documents
  FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_order_documents_insert" ON order_documents;
CREATE POLICY "anon_order_documents_insert" ON order_documents
  FOR INSERT TO anon WITH CHECK (true);
