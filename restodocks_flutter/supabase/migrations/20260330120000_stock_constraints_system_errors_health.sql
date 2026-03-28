-- Ограничения целостности склада, защита от двойного списания POS, журнал ошибок, сверка остатков.

-- Остаток на полке неотрицательный
ALTER TABLE establishment_stock_balances
  DROP CONSTRAINT IF EXISTS establishment_stock_balances_quantity_non_negative;
ALTER TABLE establishment_stock_balances
  ADD CONSTRAINT establishment_stock_balances_quantity_non_negative
  CHECK (quantity_grams >= 0);

-- Связь движения со строкой счёта (для уникальности списания по позиции × продукт)
ALTER TABLE establishment_stock_movements
  ADD COLUMN IF NOT EXISTS pos_order_line_id UUID REFERENCES pos_order_lines(id) ON DELETE SET NULL;

-- Списание продажи: дельта не положительная (уход со склада)
ALTER TABLE establishment_stock_movements
  DROP CONSTRAINT IF EXISTS establishment_stock_movements_pos_sale_delta_sign;
ALTER TABLE establishment_stock_movements
  ADD CONSTRAINT establishment_stock_movements_pos_sale_delta_sign
  CHECK (reason <> 'pos_sale' OR delta_grams <= 0);

-- Один раз списать один ингредиент (продукт) по одной строке счёта при продаже
CREATE UNIQUE INDEX IF NOT EXISTS idx_est_stock_mov_unique_pos_sale_line_product
  ON establishment_stock_movements (pos_order_line_id, product_id)
  WHERE pos_order_line_id IS NOT NULL AND reason = 'pos_sale';

COMMENT ON COLUMN establishment_stock_movements.pos_order_line_id IS 'Строка pos_order_lines; для pos_sale — защита от повторного списания.';

-- Новая сигнатура RPC (старая удаляется)
DROP FUNCTION IF EXISTS apply_establishment_stock_delta(UUID, UUID, NUMERIC, TEXT, UUID);

CREATE OR REPLACE FUNCTION apply_establishment_stock_delta(
  p_establishment_id UUID,
  p_product_id UUID,
  p_delta_grams NUMERIC,
  p_reason TEXT,
  p_pos_order_id UUID,
  p_pos_order_line_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_reason = 'pos_sale' AND p_delta_grams > 0 THEN
    RAISE EXCEPTION 'pos_sale delta must be <= 0';
  END IF;
  INSERT INTO establishment_stock_movements (
    establishment_id, product_id, delta_grams, reason, pos_order_id, pos_order_line_id
  ) VALUES (
    p_establishment_id, p_product_id, p_delta_grams, p_reason, p_pos_order_id, p_pos_order_line_id
  );
  INSERT INTO establishment_stock_balances (establishment_id, product_id, quantity_grams, updated_at)
  VALUES (p_establishment_id, p_product_id, p_delta_grams, NOW())
  ON CONFLICT (establishment_id, product_id)
  DO UPDATE SET
    quantity_grams = establishment_stock_balances.quantity_grams + EXCLUDED.quantity_grams,
    updated_at = NOW();
END;
$$;

COMMENT ON FUNCTION apply_establishment_stock_delta(UUID, UUID, NUMERIC, TEXT, UUID, UUID) IS 'Движение + остаток; pos_sale с pos_order_line_id предотвращает дубль.';

GRANT EXECUTE ON FUNCTION apply_establishment_stock_delta(UUID, UUID, NUMERIC, TEXT, UUID, UUID) TO anon, authenticated;

-- Журнал критических ошибок (клиент / будущие Edge Functions)
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
CREATE POLICY "anon_system_errors_all" ON system_errors
  FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_system_errors_all" ON system_errors;
CREATE POLICY "auth_system_errors_all" ON system_errors
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Сверка: сумма движений по продукту vs остаток в balances (внутренняя целостность)
CREATE OR REPLACE FUNCTION warehouse_health_check(p_establishment_id UUID)
RETURNS TABLE (
  product_id UUID,
  balance_grams NUMERIC,
  sum_movements_grams NUMERIC,
  diff_grams NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH mov AS (
    SELECT m.product_id, SUM(m.delta_grams) AS s
    FROM establishment_stock_movements m
    WHERE m.establishment_id = p_establishment_id
    GROUP BY m.product_id
  ),
  bal AS (
    SELECT b.product_id, b.quantity_grams
    FROM establishment_stock_balances b
    WHERE b.establishment_id = p_establishment_id
  ),
  u AS (
    SELECT product_id FROM mov
    UNION
    SELECT product_id FROM bal
  )
  SELECT
    u.product_id,
    COALESCE(bal.quantity_grams, 0)::NUMERIC AS balance_grams,
    COALESCE(mov.s, 0)::NUMERIC AS sum_movements_grams,
    (COALESCE(bal.quantity_grams, 0) - COALESCE(mov.s, 0))::NUMERIC AS diff_grams
  FROM u
  LEFT JOIN mov ON mov.product_id = u.product_id
  LEFT JOIN bal ON bal.product_id = u.product_id
  WHERE ABS(COALESCE(bal.quantity_grams, 0) - COALESCE(mov.s, 0)) > 0.0001;
$$;

COMMENT ON FUNCTION warehouse_health_check IS 'Расхождение остатка и суммы движений по продуктам (дрейф данных).';

GRANT EXECUTE ON FUNCTION warehouse_health_check(UUID) TO anon, authenticated;
