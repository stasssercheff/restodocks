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

-- --- 20260328280000_pos_cash_shifts_disbursements.sql ---
CREATE TABLE IF NOT EXISTS pos_cash_shifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  opening_balance NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (opening_balance >= 0),
  closing_balance NUMERIC(14, 2),
  opened_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  closed_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_cash_one_open_shift
  ON pos_cash_shifts(establishment_id)
  WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pos_cash_shifts_est_started ON pos_cash_shifts(establishment_id, started_at DESC);

COMMENT ON TABLE pos_cash_shifts IS 'Смена кассы зала: остаток на начало/конец (для отчёта).';

ALTER TABLE pos_cash_shifts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_cash_shifts_all" ON pos_cash_shifts;
CREATE POLICY "anon_pos_cash_shifts_all" ON pos_cash_shifts
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_cash_shifts_all" ON pos_cash_shifts;
CREATE POLICY "auth_pos_cash_shifts_all" ON pos_cash_shifts
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS pos_cash_disbursements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  shift_id UUID REFERENCES pos_cash_shifts(id) ON DELETE SET NULL,
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  purpose TEXT NOT NULL,
  recipient_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  recipient_name TEXT,
  created_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pos_cash_disb_est ON pos_cash_disbursements(establishment_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_cash_disb_shift ON pos_cash_disbursements(shift_id);

COMMENT ON TABLE pos_cash_disbursements IS 'Выдача из кассы: поставщики, аванс, прочее (назначение в purpose).';

ALTER TABLE pos_cash_disbursements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_cash_disbursements_all" ON pos_cash_disbursements;
CREATE POLICY "anon_pos_cash_disbursements_all" ON pos_cash_disbursements
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_cash_disbursements_all" ON pos_cash_disbursements;
CREATE POLICY "auth_pos_cash_disbursements_all" ON pos_cash_disbursements
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- --- 20260329120000_pos_stock_ttk_change_requests.sql ---
-- (см. файл миграции; копия для SQL Editor)
CREATE TABLE IF NOT EXISTS establishment_stock_balances (
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity_grams NUMERIC(18, 4) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (establishment_id, product_id)
);
CREATE INDEX IF NOT EXISTS idx_est_stock_balances_est ON establishment_stock_balances(establishment_id);
ALTER TABLE establishment_stock_balances ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_establishment_stock_balances_all" ON establishment_stock_balances;
CREATE POLICY "anon_establishment_stock_balances_all" ON establishment_stock_balances FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_establishment_stock_balances_all" ON establishment_stock_balances;
CREATE POLICY "auth_establishment_stock_balances_all" ON establishment_stock_balances FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS establishment_stock_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  delta_grams NUMERIC(18, 4) NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN ('pos_sale', 'adjustment', 'import')),
  pos_order_id UUID REFERENCES pos_orders(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_est_stock_mov_est_created ON establishment_stock_movements(establishment_id, created_at DESC);
ALTER TABLE establishment_stock_movements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_establishment_stock_movements_all" ON establishment_stock_movements;
CREATE POLICY "anon_establishment_stock_movements_all" ON establishment_stock_movements FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_establishment_stock_movements_all" ON establishment_stock_movements;
CREATE POLICY "auth_establishment_stock_movements_all" ON establishment_stock_movements FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS tech_card_change_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  tech_card_id UUID NOT NULL REFERENCES tech_cards(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  proposed_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  author_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  resolved_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  resolution_note TEXT
);
CREATE INDEX IF NOT EXISTS idx_ttk_change_req_est_status ON tech_card_change_requests(establishment_id, status, created_at DESC);
ALTER TABLE tech_card_change_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_tech_card_change_requests_all" ON tech_card_change_requests;
CREATE POLICY "anon_tech_card_change_requests_all" ON tech_card_change_requests FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_tech_card_change_requests_all" ON tech_card_change_requests;
CREATE POLICY "auth_tech_card_change_requests_all" ON tech_card_change_requests FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION apply_establishment_stock_delta(
  p_establishment_id UUID, p_product_id UUID, p_delta_grams NUMERIC, p_reason TEXT, p_pos_order_id UUID
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO establishment_stock_movements (establishment_id, product_id, delta_grams, reason, pos_order_id)
  VALUES (p_establishment_id, p_product_id, p_delta_grams, p_reason, p_pos_order_id);
  INSERT INTO establishment_stock_balances (establishment_id, product_id, quantity_grams, updated_at)
  VALUES (p_establishment_id, p_product_id, p_delta_grams, NOW())
  ON CONFLICT (establishment_id, product_id) DO UPDATE SET
    quantity_grams = establishment_stock_balances.quantity_grams + EXCLUDED.quantity_grams, updated_at = NOW();
END; $$;
GRANT EXECUTE ON FUNCTION apply_establishment_stock_delta(UUID, UUID, NUMERIC, TEXT, UUID) TO anon, authenticated;

-- --- 20260330120000_stock_constraints_system_errors_health.sql ---
ALTER TABLE establishment_stock_balances DROP CONSTRAINT IF EXISTS establishment_stock_balances_quantity_non_negative;
ALTER TABLE establishment_stock_balances ADD CONSTRAINT establishment_stock_balances_quantity_non_negative CHECK (quantity_grams >= 0);
ALTER TABLE establishment_stock_movements ADD COLUMN IF NOT EXISTS pos_order_line_id UUID REFERENCES pos_order_lines(id) ON DELETE SET NULL;
ALTER TABLE establishment_stock_movements DROP CONSTRAINT IF EXISTS establishment_stock_movements_pos_sale_delta_sign;
ALTER TABLE establishment_stock_movements ADD CONSTRAINT establishment_stock_movements_pos_sale_delta_sign CHECK (reason <> 'pos_sale' OR delta_grams <= 0);
CREATE UNIQUE INDEX IF NOT EXISTS idx_est_stock_mov_unique_pos_sale_line_product ON establishment_stock_movements (pos_order_line_id, product_id) WHERE pos_order_line_id IS NOT NULL AND reason = 'pos_sale';
DROP FUNCTION IF EXISTS apply_establishment_stock_delta(UUID, UUID, NUMERIC, TEXT, UUID);
CREATE OR REPLACE FUNCTION apply_establishment_stock_delta(
  p_establishment_id UUID, p_product_id UUID, p_delta_grams NUMERIC, p_reason TEXT, p_pos_order_id UUID, p_pos_order_line_id UUID DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_reason = 'pos_sale' AND p_delta_grams > 0 THEN RAISE EXCEPTION 'pos_sale delta must be <= 0'; END IF;
  INSERT INTO establishment_stock_movements (establishment_id, product_id, delta_grams, reason, pos_order_id, pos_order_line_id)
  VALUES (p_establishment_id, p_product_id, p_delta_grams, p_reason, p_pos_order_id, p_pos_order_line_id);
  INSERT INTO establishment_stock_balances (establishment_id, product_id, quantity_grams, updated_at)
  VALUES (p_establishment_id, p_product_id, p_delta_grams, NOW())
  ON CONFLICT (establishment_id, product_id) DO UPDATE SET
    quantity_grams = establishment_stock_balances.quantity_grams + EXCLUDED.quantity_grams, updated_at = NOW();
END; $$;
GRANT EXECUTE ON FUNCTION apply_establishment_stock_delta(UUID, UUID, NUMERIC, TEXT, UUID, UUID) TO anon, authenticated;
CREATE TABLE IF NOT EXISTS system_errors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  establishment_id UUID REFERENCES establishments(id) ON DELETE CASCADE,
  severity TEXT NOT NULL DEFAULT 'error' CHECK (severity IN ('warning', 'error', 'critical')),
  source TEXT NOT NULL DEFAULT 'client',
  message TEXT NOT NULL,
  context JSONB NOT NULL DEFAULT '{}'::jsonb,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  pos_order_id UUID REFERENCES pos_orders(id) ON DELETE SET NULL,
  pos_order_line_id UUID REFERENCES pos_order_lines(id) ON DELETE SET NULL,
  dining_table_id UUID REFERENCES pos_dining_tables(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_system_errors_est_created ON system_errors(establishment_id, created_at DESC);
ALTER TABLE system_errors ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_system_errors_all" ON system_errors;
CREATE POLICY "anon_system_errors_all" ON system_errors FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_system_errors_all" ON system_errors;
CREATE POLICY "auth_system_errors_all" ON system_errors FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE OR REPLACE FUNCTION warehouse_health_check(p_establishment_id UUID)
RETURNS TABLE (product_id UUID, balance_grams NUMERIC, sum_movements_grams NUMERIC, diff_grams NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH mov AS (SELECT m.product_id, SUM(m.delta_grams) AS s FROM establishment_stock_movements m WHERE m.establishment_id = p_establishment_id GROUP BY m.product_id),
  bal AS (SELECT b.product_id, b.quantity_grams FROM establishment_stock_balances b WHERE b.establishment_id = p_establishment_id),
  u AS (SELECT product_id FROM mov UNION SELECT product_id FROM bal)
  SELECT u.product_id, COALESCE(bal.quantity_grams, 0)::NUMERIC, COALESCE(mov.s, 0)::NUMERIC,
    (COALESCE(bal.quantity_grams, 0) - COALESCE(mov.s, 0))::NUMERIC
  FROM u LEFT JOIN mov ON mov.product_id = u.product_id LEFT JOIN bal ON bal.product_id = u.product_id
  WHERE ABS(COALESCE(bal.quantity_grams, 0) - COALESCE(mov.s, 0)) > 0.0001;
$$;
GRANT EXECUTE ON FUNCTION warehouse_health_check(UUID) TO anon, authenticated;

-- =============================================================================
-- Готово. В Table Editor должна появиться pos_dining_tables; 404 на REST уйдёт.
-- =============================================================================
