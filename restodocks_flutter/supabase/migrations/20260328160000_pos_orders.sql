-- Черновики и активные заказы зала (привязка к столу).
CREATE TABLE IF NOT EXISTS pos_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  dining_table_id UUID NOT NULL REFERENCES pos_dining_tables(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'closed')),
  guest_count INT NOT NULL DEFAULT 1 CHECK (guest_count >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pos_orders_establishment ON pos_orders(establishment_id);
CREATE INDEX IF NOT EXISTS idx_pos_orders_table ON pos_orders(dining_table_id);
CREATE INDEX IF NOT EXISTS idx_pos_orders_active ON pos_orders(establishment_id, status)
  WHERE status <> 'closed';

COMMENT ON TABLE pos_orders IS 'Заказы зала: черновик, отправлен на кухню/бар, закрыт.';

ALTER TABLE pos_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_orders_all" ON pos_orders;
CREATE POLICY "anon_pos_orders_all" ON pos_orders
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_orders_all" ON pos_orders;
CREATE POLICY "auth_pos_orders_all" ON pos_orders
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
