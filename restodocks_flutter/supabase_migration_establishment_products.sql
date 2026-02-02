-- Номенклатура заведения: связь establishment <-> product
-- products — общий справочник, establishment_products — что в номенклатуре заведения

CREATE TABLE IF NOT EXISTS establishment_products (
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (establishment_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_establishment_products_est 
  ON establishment_products(establishment_id);
CREATE INDEX IF NOT EXISTS idx_establishment_products_prod 
  ON establishment_products(product_id);

COMMENT ON TABLE establishment_products IS 'Номенклатура: продукты, выбранные заведением из справочника';
