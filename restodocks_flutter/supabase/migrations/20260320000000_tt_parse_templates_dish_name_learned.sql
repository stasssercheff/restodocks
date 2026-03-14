-- Обучение: выученная позиция названия блюда (где искать при парсинге).
-- При правке пользователя ищем corrected в rows и сохраняем (row_offset, col).
-- Отдельная таблица — не требует существования tt_parse_templates.
CREATE TABLE IF NOT EXISTS tt_parse_learned_dish_name (
  header_signature text PRIMARY KEY,
  dish_name_row_offset int NOT NULL,
  dish_name_col int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE tt_parse_learned_dish_name IS 'Обучение: при правке пользователь указал откуда брать название. Общая таблица — один обученный шаблон помогает всем заведениям (без establishment_id).';

ALTER TABLE tt_parse_learned_dish_name ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
CREATE POLICY "authenticated_select_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
CREATE POLICY "authenticated_insert_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
CREATE POLICY "authenticated_update_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR UPDATE TO authenticated USING (true);
