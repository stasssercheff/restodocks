-- Политики RLS для authenticated: владельцы и шефы входят через Supabase Auth,
-- поэтому SELECT/INSERT должны работать для роли authenticated (не только anon).
-- Без этого инвентаризация и заказы сохраняются, но не появляются во входящих.

-- inventory_documents
DROP POLICY IF EXISTS "auth_inventory_documents_select" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_select" ON inventory_documents
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_insert" ON inventory_documents
  FOR INSERT TO authenticated WITH CHECK (true);

-- order_documents
DROP POLICY IF EXISTS "auth_order_documents_select" ON order_documents;
CREATE POLICY "auth_order_documents_select" ON order_documents
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_order_documents_insert" ON order_documents;
CREATE POLICY "auth_order_documents_insert" ON order_documents
  FOR INSERT TO authenticated WITH CHECK (true);
