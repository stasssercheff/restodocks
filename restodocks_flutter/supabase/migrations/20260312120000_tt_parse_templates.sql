-- Шаблоны парсинга ТТК, сохранённые после успешной обработки через ИИ.
-- Следующая загрузка того же формата (branck) парсится без ИИ.

CREATE TABLE IF NOT EXISTS tt_parse_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  header_signature text NOT NULL,
  header_row_index int NOT NULL DEFAULT 0,
  name_col int NOT NULL DEFAULT 0,
  product_col int NOT NULL DEFAULT 1,
  gross_col int NOT NULL DEFAULT -1,
  net_col int NOT NULL DEFAULT -1,
  waste_col int NOT NULL DEFAULT -1,
  source text, -- excel, docx, pdf
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tt_parse_templates_signature_unique ON tt_parse_templates (header_signature);

COMMENT ON TABLE tt_parse_templates IS 'Обучение: шаблоны колонок ТТК, выведенные из ИИ для последующего парсинга без ИИ';

ALTER TABLE tt_parse_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_select_tt_parse_templates" ON tt_parse_templates
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated_insert_tt_parse_templates" ON tt_parse_templates
  FOR INSERT TO authenticated WITH CHECK (true);
