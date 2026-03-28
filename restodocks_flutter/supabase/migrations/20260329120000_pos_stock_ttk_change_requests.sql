-- Остатки по продуктам (граммы) + движения; заявки на изменение ТТК (согласование владельцем).

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
CREATE POLICY "anon_establishment_stock_balances_all" ON establishment_stock_balances
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_establishment_stock_balances_all" ON establishment_stock_balances;
CREATE POLICY "auth_establishment_stock_balances_all" ON establishment_stock_balances
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

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
CREATE POLICY "anon_establishment_stock_movements_all" ON establishment_stock_movements
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_establishment_stock_movements_all" ON establishment_stock_movements;
CREATE POLICY "auth_establishment_stock_movements_all" ON establishment_stock_movements
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

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
CREATE POLICY "anon_tech_card_change_requests_all" ON tech_card_change_requests
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_tech_card_change_requests_all" ON tech_card_change_requests;
CREATE POLICY "auth_tech_card_change_requests_all" ON tech_card_change_requests
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION apply_establishment_stock_delta(
  p_establishment_id UUID,
  p_product_id UUID,
  p_delta_grams NUMERIC,
  p_reason TEXT,
  p_pos_order_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO establishment_stock_movements (
    establishment_id, product_id, delta_grams, reason, pos_order_id
  ) VALUES (
    p_establishment_id, p_product_id, p_delta_grams, p_reason, p_pos_order_id
  );
  INSERT INTO establishment_stock_balances (establishment_id, product_id, quantity_grams, updated_at)
  VALUES (p_establishment_id, p_product_id, p_delta_grams, NOW())
  ON CONFLICT (establishment_id, product_id)
  DO UPDATE SET
    quantity_grams = establishment_stock_balances.quantity_grams + EXCLUDED.quantity_grams,
    updated_at = NOW();
END;
$$;

COMMENT ON FUNCTION apply_establishment_stock_delta IS 'Атомарно: движение + пересчёт остатка (граммы).';

GRANT EXECUTE ON FUNCTION apply_establishment_stock_delta(UUID, UUID, NUMERIC, TEXT, UUID) TO anon, authenticated;
