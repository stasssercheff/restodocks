-- Правки пользователя: original → corrected. При следующем парсинге того же формата — подставляем corrected.
CREATE TABLE IF NOT EXISTS tt_parse_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid REFERENCES establishments(id) ON DELETE CASCADE,
  header_signature text NOT NULL,
  field text NOT NULL,
  original_value text,
  corrected_value text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tt_parse_corrections_lookup
  ON tt_parse_corrections (header_signature, field, original_value);

CREATE INDEX IF NOT EXISTS idx_tt_parse_corrections_establishment
  ON tt_parse_corrections (establishment_id) WHERE establishment_id IS NOT NULL;

COMMENT ON TABLE tt_parse_corrections IS 'Обучение на правках: при повторном парсинге подставляем corrected вместо original';

ALTER TABLE tt_parse_corrections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_select_tt_parse_corrections" ON tt_parse_corrections
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated_insert_tt_parse_corrections" ON tt_parse_corrections
  FOR INSERT TO authenticated WITH CHECK (true);
