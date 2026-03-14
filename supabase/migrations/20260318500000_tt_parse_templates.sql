-- Шаблоны парсинга ТТК (обучение). Нужна для tt-parse-save-learning.
-- Без этой таблицы Edge Function возвращает 500 при сохранении шаблона.
CREATE TABLE IF NOT EXISTS tt_parse_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  header_signature text NOT NULL,
  header_row_index int NOT NULL DEFAULT 0,
  name_col int NOT NULL DEFAULT 0,
  product_col int NOT NULL DEFAULT 1,
  gross_col int NOT NULL DEFAULT -1,
  net_col int NOT NULL DEFAULT -1,
  waste_col int NOT NULL DEFAULT -1,
  output_col int NOT NULL DEFAULT -1,
  source text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tt_parse_templates_signature_unique ON tt_parse_templates (header_signature);

ALTER TABLE tt_parse_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_tt_parse_templates" ON tt_parse_templates;
CREATE POLICY "authenticated_select_tt_parse_templates" ON tt_parse_templates
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_tt_parse_templates" ON tt_parse_templates;
CREATE POLICY "authenticated_insert_tt_parse_templates" ON tt_parse_templates
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_tt_parse_templates" ON tt_parse_templates;
CREATE POLICY "authenticated_update_tt_parse_templates" ON tt_parse_templates
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
