-- Legacy login (authenticate-employee) не даёт Supabase JWT → клиент остаётся anon.
-- tt_parse_* upsert/select с клиента падали 400/403. Добавляем anon-политики.
-- Данные не секретны: индексы колонок, правки парсинга.

-- tt_parse_templates
CREATE POLICY "anon_select_tt_parse_templates" ON tt_parse_templates
  FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_tt_parse_templates" ON tt_parse_templates
  FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_update_tt_parse_templates" ON tt_parse_templates
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- tt_parse_learned_dish_name
CREATE POLICY "anon_select_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_update_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- tt_parse_corrections
CREATE POLICY "anon_select_tt_parse_corrections" ON tt_parse_corrections
  FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_tt_parse_corrections" ON tt_parse_corrections
  FOR INSERT TO anon WITH CHECK (true);
