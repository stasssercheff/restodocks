-- История изменений цены продукта в номенклатуре заведения
CREATE TABLE IF NOT EXISTS product_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  old_price REAL,
  new_price REAL NOT NULL,
  currency TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_price_history_est_prod
  ON product_price_history(establishment_id, product_id);

CREATE INDEX IF NOT EXISTS idx_product_price_history_changed_at
  ON product_price_history(changed_at DESC);

COMMENT ON TABLE product_price_history IS 'История изменений цены продукта в номенклатуре заведения';

ALTER TABLE product_price_history ENABLE ROW LEVEL SECURITY;

-- Просмотр истории — сотрудники своего заведения
CREATE POLICY "auth_select_product_price_history" ON product_price_history
  FOR SELECT USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  );

-- Вставка — сотрудники своего заведения
CREATE POLICY "auth_insert_product_price_history" ON product_price_history
  FOR INSERT WITH CHECK (
    establishment_id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  );
