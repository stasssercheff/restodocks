-- Обучение: колонка «Технология» — выводится из правок пользователя.
ALTER TABLE tt_parse_learned_dish_name
  ADD COLUMN IF NOT EXISTS technology_col int;

COMMENT ON COLUMN tt_parse_learned_dish_name.technology_col IS 'Колонка «Технология приготовления». NULL=из шаблона';
