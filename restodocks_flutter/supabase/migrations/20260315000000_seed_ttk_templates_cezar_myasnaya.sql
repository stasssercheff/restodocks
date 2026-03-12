-- Шаблоны ТТК iiko: Цезарь (ГОСТ 2-row), Мясная к пенному (тот же что печеная свекла)
-- Excel/DOCX/PDF — одинаково, без AI.

-- Цезарь (ГОСТ): row0 "Наименование сырья и продуктов | Расход сырья на 1 порцию", row1 "| Брутто | Нетто"
-- Матчим по row0, data с row2 (header_row_index=1)
INSERT INTO tt_parse_templates (header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, source)
VALUES (
  'наименование сырья и продуктов|расход сырья на 1 порцию',
  1, 0, 0, 1, 2, -1, -1, 'excel'
)
ON CONFLICT (header_signature) DO UPDATE SET
  header_row_index = EXCLUDED.header_row_index,
  name_col = EXCLUDED.name_col,
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  net_col = EXCLUDED.net_col,
  waste_col = EXCLUDED.waste_col,
  output_col = EXCLUDED.output_col,
  source = EXCLUDED.source;

-- Мясная к пенному / iiko с полным набором колонок (как печеная свекла)
-- Уже есть в 20260312140000, но на случай вариаций — product_col 2 при пустой col1
