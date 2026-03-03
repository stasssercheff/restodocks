-- 1. Номенклатура по отделам: bar и kitchen имеют отдельные списки продуктов
ALTER TABLE establishment_products ADD COLUMN IF NOT EXISTS department TEXT DEFAULT 'kitchen' NOT NULL;
COMMENT ON COLUMN establishment_products.department IS 'Отдел номенклатуры: kitchen, bar. По умолчанию kitchen.';

UPDATE establishment_products SET department = 'kitchen' WHERE department IS NULL;

-- Уникальность: один продукт может быть и в кухне, и в баре
ALTER TABLE establishment_products DROP CONSTRAINT IF EXISTS establishment_products_establishment_id_product_id_key;
ALTER TABLE establishment_products ADD CONSTRAINT establishment_products_est_product_dept_key
  UNIQUE (establishment_id, product_id, department);

-- 2. ТТК по отделам: ТТК кухни и ТТК бара не пересекаются
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS department TEXT DEFAULT 'kitchen';
COMMENT ON COLUMN tech_cards.department IS 'Отдел: kitchen, bar. ТТК кухни и бара разделены.';

UPDATE tech_cards SET department = 'kitchen' WHERE department IS NULL;
