-- Обучение: выученные индексы колонок (product, gross, net) из правок пользователя.
ALTER TABLE tt_parse_learned_dish_name
  ADD COLUMN IF NOT EXISTS product_col int,
  ADD COLUMN IF NOT EXISTS gross_col int,
  ADD COLUMN IF NOT EXISTS net_col int;

COMMENT ON COLUMN tt_parse_learned_dish_name.product_col IS 'Колонка с названием продукта. NULL=из шаблона';
COMMENT ON COLUMN tt_parse_learned_dish_name.gross_col IS 'Колонка брутто. NULL=из шаблона';
COMMENT ON COLUMN tt_parse_learned_dish_name.net_col IS 'Колонка нетто. NULL=из шаблона';
