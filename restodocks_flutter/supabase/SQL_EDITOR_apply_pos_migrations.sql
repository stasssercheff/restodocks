-- =============================================================================
-- POS: столы и заказы — один прогон в Supabase → SQL Editor, если миграции
-- ни разу не применялись к этому проекту (ошибка 404 на pos_dining_tables).
-- Ожидаются уже существующие таблицы: establishments, tech_cards.
-- В проде предпочтительно: supabase link + supabase db push (как у вас принято).
-- =============================================================================

-- --- 20260328130000_pos_dining_tables.sql ---
CREATE TABLE IF NOT EXISTS pos_dining_tables (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  floor_name TEXT,
  room_name TEXT,
  table_number INT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'free' CHECK (status IN ('free', 'occupied', 'bill_requested')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS pos_dining_tables_unique_place
  ON pos_dining_tables (
    establishment_id,
    COALESCE(floor_name, ''),
    COALESCE(room_name, ''),
    table_number
  );

CREATE INDEX IF NOT EXISTS idx_pos_dining_tables_establishment
  ON pos_dining_tables (establishment_id);

COMMENT ON TABLE pos_dining_tables IS 'Столы заведения для зала: группировка по этажу и залу, статус для индикации.';

ALTER TABLE pos_dining_tables ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_dining_tables_all" ON pos_dining_tables;
CREATE POLICY "anon_pos_dining_tables_all" ON pos_dining_tables
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_dining_tables_all" ON pos_dining_tables;
CREATE POLICY "auth_pos_dining_tables_all" ON pos_dining_tables
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- --- 20260328140000_pos_dining_tables_seed_demo.sql ---
INSERT INTO pos_dining_tables (
  establishment_id,
  floor_name,
  room_name,
  table_number,
  sort_order,
  status
)
SELECT
  e.id,
  '1',
  'Основной',
  gs.n::int,
  (gs.n - 1)::int,
  'free'
FROM establishments e
CROSS JOIN generate_series(1, 3) AS gs(n)
WHERE NOT EXISTS (
  SELECT 1 FROM pos_dining_tables p WHERE p.establishment_id = e.id
);

COMMENT ON TABLE pos_dining_tables IS 'Столы заведения. После первой миграции с seed у каждого заведения без столов добавляются 3 демо-стола (этаж 1, зал «Основной»).';

-- --- 20260328160000_pos_orders.sql ---
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

-- --- 20260328170000_pos_order_lines.sql ---
CREATE TABLE IF NOT EXISTS pos_order_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
  tech_card_id UUID NOT NULL REFERENCES tech_cards(id) ON DELETE RESTRICT,
  quantity NUMERIC NOT NULL DEFAULT 1 CHECK (quantity > 0),
  comment TEXT,
  course_number INT NOT NULL DEFAULT 1 CHECK (course_number >= 1),
  guest_number INT CHECK (guest_number IS NULL OR guest_number >= 1),
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pos_order_lines_order ON pos_order_lines(order_id);
CREATE INDEX IF NOT EXISTS idx_pos_order_lines_tech_card ON pos_order_lines(tech_card_id);

COMMENT ON TABLE pos_order_lines IS 'Позиции счёта зала: ТТК, количество порций, комментарий, курс подачи, номер гостя.';

ALTER TABLE pos_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_order_lines_all" ON pos_order_lines;
CREATE POLICY "anon_pos_order_lines_all" ON pos_order_lines
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_order_lines_all" ON pos_order_lines;
CREATE POLICY "auth_pos_order_lines_all" ON pos_order_lines
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- --- 20260328200000_pos_order_lines_served_at.sql ---
ALTER TABLE pos_order_lines
  ADD COLUMN IF NOT EXISTS served_at TIMESTAMPTZ;

COMMENT ON COLUMN pos_order_lines.served_at IS 'Время отдачи гостю; NULL — ещё в работе/ожидает.';

-- --- 20260328210000_pos_orders_payment.sql ---
ALTER TABLE pos_orders
  ADD COLUMN IF NOT EXISTS payment_method TEXT
    CHECK (payment_method IS NULL OR payment_method IN ('cash', 'card', 'transfer', 'other'));
ALTER TABLE pos_orders
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

COMMENT ON COLUMN pos_orders.payment_method IS 'Способ оплаты при закрытии: cash | card | transfer | other.';
COMMENT ON COLUMN pos_orders.paid_at IS 'Момент фиксации оплаты (UTC).';

-- --- 20260328240000_pos_dining_one_default_table.sql ---
DELETE FROM pos_dining_tables
WHERE table_number IN (2, 3)
  AND floor_name IS NOT DISTINCT FROM '1'
  AND room_name IS NOT DISTINCT FROM 'Основной';

COMMENT ON TABLE pos_dining_tables IS 'Столы заведения: этаж и зал — произвольные подписи (настраивает владелец / управляющий зала). По умолчанию один стол.';

-- --- 20260328260000_pos_orders_pricing_split_payments.sql ---
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

-- --- 20260328270000_fiscal_core_outbox_settings.sql ---
-- (см. файл миграции; для краткости — ключевые объекты)
CREATE TABLE IF NOT EXISTS establishment_fiscal_settings (
  establishment_id UUID PRIMARY KEY REFERENCES establishments(id) ON DELETE CASCADE,
  tax_region TEXT NOT NULL DEFAULT 'RU',
  price_tax_mode TEXT NOT NULL DEFAULT 'tax_included'
    CHECK (price_tax_mode IN ('tax_included', 'tax_excluded')),
  vat_override_percent NUMERIC(6, 2)
    CHECK (vat_override_percent IS NULL OR (vat_override_percent >= 0 AND vat_override_percent <= 100)),
  fiscal_section_id TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE establishment_fiscal_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_establishment_fiscal_settings_all" ON establishment_fiscal_settings;
CREATE POLICY "anon_establishment_fiscal_settings_all" ON establishment_fiscal_settings
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_establishment_fiscal_settings_all" ON establishment_fiscal_settings;
CREATE POLICY "auth_establishment_fiscal_settings_all" ON establishment_fiscal_settings
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS fiscal_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  pos_order_id UUID REFERENCES pos_orders(id) ON DELETE SET NULL,
  operation TEXT NOT NULL CHECK (operation IN ('sale', 'refund', 'correction')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'synced', 'failed', 'skipped')),
  client_request_id UUID NOT NULL UNIQUE,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fiscal_outbox_establishment ON fiscal_outbox(establishment_id);
ALTER TABLE fiscal_outbox ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_fiscal_outbox_all" ON fiscal_outbox;
CREATE POLICY "anon_fiscal_outbox_all" ON fiscal_outbox
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_fiscal_outbox_all" ON fiscal_outbox;
CREATE POLICY "auth_fiscal_outbox_all" ON fiscal_outbox
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS fiscal_system_tag TEXT;

-- =============================================================================
-- Готово. В Table Editor должна появиться pos_dining_tables; 404 на REST уйдёт.
-- =============================================================================
