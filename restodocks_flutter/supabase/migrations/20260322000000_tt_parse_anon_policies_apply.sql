-- Копия для ручного запуска в Supabase SQL Editor.
-- Если политики уже есть — DROP не упадёт, CREATE создаст заново.

DROP POLICY IF EXISTS "anon_select_tt_parse_templates" ON tt_parse_templates;
DROP POLICY IF EXISTS "anon_insert_tt_parse_templates" ON tt_parse_templates;
DROP POLICY IF EXISTS "anon_update_tt_parse_templates" ON tt_parse_templates;
CREATE POLICY "anon_select_tt_parse_templates" ON tt_parse_templates FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_tt_parse_templates" ON tt_parse_templates FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_update_tt_parse_templates" ON tt_parse_templates FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_select_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
DROP POLICY IF EXISTS "anon_insert_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
DROP POLICY IF EXISTS "anon_update_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
CREATE POLICY "anon_select_tt_parse_learned_dish" ON tt_parse_learned_dish_name FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_tt_parse_learned_dish" ON tt_parse_learned_dish_name FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_update_tt_parse_learned_dish" ON tt_parse_learned_dish_name FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_select_tt_parse_corrections" ON tt_parse_corrections;
DROP POLICY IF EXISTS "anon_insert_tt_parse_corrections" ON tt_parse_corrections;
CREATE POLICY "anon_select_tt_parse_corrections" ON tt_parse_corrections FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_tt_parse_corrections" ON tt_parse_corrections FOR INSERT TO anon WITH CHECK (true);
