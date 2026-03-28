-- Фиксация оплаты при закрытии счёта (без фискального чека — только учёт в приложении).
ALTER TABLE pos_orders
  ADD COLUMN IF NOT EXISTS payment_method TEXT
    CHECK (payment_method IS NULL OR payment_method IN ('cash', 'card', 'transfer', 'other'));
ALTER TABLE pos_orders
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

COMMENT ON COLUMN pos_orders.payment_method IS 'Способ оплаты при закрытии: cash | card | transfer | other.';
COMMENT ON COLUMN pos_orders.paid_at IS 'Момент фиксации оплаты (UTC).';
