-- Скидка, сервисный сбор, чаевые; раздельная оплата (несколько способов на один счёт).
ALTER TABLE pos_orders
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(14, 2) NOT NULL DEFAULT 0
    CHECK (discount_amount >= 0);
ALTER TABLE pos_orders
  ADD COLUMN IF NOT EXISTS service_charge_percent NUMERIC(7, 2) NOT NULL DEFAULT 0
    CHECK (service_charge_percent >= 0 AND service_charge_percent <= 100);
ALTER TABLE pos_orders
  ADD COLUMN IF NOT EXISTS tips_amount NUMERIC(14, 2) NOT NULL DEFAULT 0
    CHECK (tips_amount >= 0);

COMMENT ON COLUMN pos_orders.discount_amount IS 'Фиксированная скидка с суммы по меню (ТТК × кол-во).';
COMMENT ON COLUMN pos_orders.service_charge_percent IS 'Сервисный сбор % от суммы после скидки.';
COMMENT ON COLUMN pos_orders.tips_amount IS 'Чаевые, фиксируются при закрытии счёта.';

ALTER TABLE pos_orders DROP CONSTRAINT IF EXISTS pos_orders_payment_method_check;
ALTER TABLE pos_orders
  ADD CONSTRAINT pos_orders_payment_method_check
    CHECK (
      payment_method IS NULL
      OR payment_method IN ('cash', 'card', 'transfer', 'other', 'split')
    );

COMMENT ON COLUMN pos_orders.payment_method IS
  'Способ оплаты: один из видов или split при нескольких платежах (см. pos_order_payments).';

CREATE TABLE IF NOT EXISTS pos_order_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'card', 'transfer', 'other')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pos_order_payments_order_id ON pos_order_payments(order_id);

COMMENT ON TABLE pos_order_payments IS 'Платежи по закрытому счёту (один или несколько — разделение оплаты).';

ALTER TABLE pos_order_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_order_payments_all" ON pos_order_payments;
CREATE POLICY "anon_pos_order_payments_all" ON pos_order_payments
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_order_payments_all" ON pos_order_payments;
CREATE POLICY "auth_pos_order_payments_all" ON pos_order_payments
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
