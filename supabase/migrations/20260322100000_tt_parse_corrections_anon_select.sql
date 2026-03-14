-- Legacy-логин (authenticate-employee): anon читает tt_parse_corrections для применения правок при парсинге
-- Без этой политики _applyParseCorrections возвращает пустой результат → обучение «не работает»
DROP POLICY IF EXISTS "anon_select_tt_parse_corrections" ON tt_parse_corrections;
CREATE POLICY "anon_select_tt_parse_corrections" ON tt_parse_corrections
  FOR SELECT TO anon
  USING (true);
