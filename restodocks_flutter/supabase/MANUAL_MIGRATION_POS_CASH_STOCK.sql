-- =============================================================================
-- РУЧНОЙ ПРОГОН В SUPABASE SQL EDITOR (одним запросом или по частям).
-- Порядок: pos_orders (скидка/оплата) → касса зала → склад/ТТК → ограничения…
-- Требуются уже существующие: establishments, employees, products, pos_orders,
-- pos_order_lines, pos_dining_tables, tech_cards.
-- =============================================================================

-- ========== 0/3: 20260328260000_pos_orders_pricing_split_payments (ОБЯЗАТЕЛЬНО для POS зала) ==========
-- Без этих колонок приложение падает при создании заказа: discount_amount и др.
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

-- ========== 1/3: 20260328280000_pos_cash_shifts_disbursements ==========
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
  ON pos_cash_shifts(establishment_id) WHERE ended_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_pos_cash_shifts_est_started ON pos_cash_shifts(establishment_id, started_at DESC);
COMMENT ON TABLE pos_cash_shifts IS 'Смена кассы зала: остаток на начало/конец (для отчёта).';
ALTER TABLE pos_cash_shifts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_pos_cash_shifts_all" ON pos_cash_shifts;
CREATE POLICY "anon_pos_cash_shifts_all" ON pos_cash_shifts FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_pos_cash_shifts_all" ON pos_cash_shifts;
CREATE POLICY "auth_pos_cash_shifts_all" ON pos_cash_shifts FOR ALL TO authenticated USING (true) WITH CHECK (true);

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
CREATE POLICY "anon_pos_cash_disbursements_all" ON pos_cash_disbursements FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_pos_cash_disbursements_all" ON pos_cash_disbursements;
CREATE POLICY "auth_pos_cash_disbursements_all" ON pos_cash_disbursements FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ========== 2/3: 20260329120000_pos_stock_ttk_change_requests ==========
CREATE TABLE IF NOT EXISTS establishment_stock_balances (
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity_grams NUMERIC(18, 4) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (establishment_id, product_id)
);
CREATE INDEX IF NOT EXISTS idx_est_stock_balances_est ON establishment_stock_balances(establishment_id);
COMMENT ON TABLE establishment_stock_balances IS 'Упрощённый склад: остаток номенклатуры в граммах по заведению.';
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
CREATE INDEX IF NOT EXISTS idx_est_stock_mov_order ON establishment_stock_movements(pos_order_id);
COMMENT ON TABLE establishment_stock_movements IS 'Движения склада (в т.ч. списание при оплате счёта POS).';
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
COMMENT ON TABLE tech_card_change_requests IS 'Предложенные правки ТТК от персонала; владелец подтверждает или отклоняет.';
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

-- ========== 3/3: 20260330120000_stock_constraints_system_errors_health ==========
ALTER TABLE establishment_stock_balances DROP CONSTRAINT IF EXISTS establishment_stock_balances_quantity_non_negative;
ALTER TABLE establishment_stock_balances ADD CONSTRAINT establishment_stock_balances_quantity_non_negative CHECK (quantity_grams >= 0);
ALTER TABLE establishment_stock_movements ADD COLUMN IF NOT EXISTS pos_order_line_id UUID REFERENCES pos_order_lines(id) ON DELETE SET NULL;
ALTER TABLE establishment_stock_movements DROP CONSTRAINT IF EXISTS establishment_stock_movements_pos_sale_delta_sign;
ALTER TABLE establishment_stock_movements ADD CONSTRAINT establishment_stock_movements_pos_sale_delta_sign CHECK (reason <> 'pos_sale' OR delta_grams <= 0);
CREATE UNIQUE INDEX IF NOT EXISTS idx_est_stock_mov_unique_pos_sale_line_product
  ON establishment_stock_movements (pos_order_line_id, product_id) WHERE pos_order_line_id IS NOT NULL AND reason = 'pos_sale';
COMMENT ON COLUMN establishment_stock_movements.pos_order_line_id IS 'Строка pos_order_lines; для pos_sale — защита от повторного списания.';

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
COMMENT ON TABLE system_errors IS 'Ошибки и сбои: контекст для разбора (POS, склад, фоновые задачи).';
ALTER TABLE system_errors ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_system_errors_all" ON system_errors;
CREATE POLICY "anon_system_errors_all" ON system_errors FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_system_errors_all" ON system_errors;
CREATE POLICY "auth_system_errors_all" ON system_errors FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION warehouse_health_check(p_establishment_id UUID)
RETURNS TABLE (product_id UUID, balance_grams NUMERIC, sum_movements_grams NUMERIC, diff_grams NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH mov AS (
    SELECT m.product_id, SUM(m.delta_grams) AS s FROM establishment_stock_movements m WHERE m.establishment_id = p_establishment_id GROUP BY m.product_id
  ),
  bal AS (SELECT b.product_id, b.quantity_grams FROM establishment_stock_balances b WHERE b.establishment_id = p_establishment_id),
  u AS (SELECT product_id FROM mov UNION SELECT product_id FROM bal)
  SELECT u.product_id, COALESCE(bal.quantity_grams, 0)::NUMERIC, COALESCE(mov.s, 0)::NUMERIC,
    (COALESCE(bal.quantity_grams, 0) - COALESCE(mov.s, 0))::NUMERIC
  FROM u LEFT JOIN mov ON mov.product_id = u.product_id LEFT JOIN bal ON bal.product_id = u.product_id
  WHERE ABS(COALESCE(bal.quantity_grams, 0) - COALESCE(mov.s, 0)) > 0.0001;
$$;
GRANT EXECUTE ON FUNCTION warehouse_health_check(UUID) TO anon, authenticated;

-- =============================================================================
-- Готово. Если ошибка на UNIQUE idx_est_stock_mov_unique_pos_sale_line_product —
-- удалите дубликаты (одинаковые pos_order_line_id + product_id + pos_sale) вручную.
--
-- Edge Function log-system-error (запись system_errors с сервера): деплой отдельно:
--   cd restodocks_flutter && supabase functions deploy log-system-error
-- Таблица system_errors должна уже существовать (миграция выше).
-- =============================================================================
