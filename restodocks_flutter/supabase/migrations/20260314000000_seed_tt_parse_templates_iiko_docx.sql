-- Шаблон для iiko DOCX: № | Наименование продукта | Ед. изм. | Брутто в ед. изм. | Вес брутто, кг | Вес нетто, кг
-- Вариант без «или п/ф» в заголовке нетто (часто в экспорте DOCX)
INSERT INTO tt_parse_templates (header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, source)
VALUES (
  '№|наименование продукта|ед. изм.|брутто в ед. изм.|вес брутто, кг|вес нетто, кг',
  0, 0, 1, 4, 5, -1, -1, 'docx'
)
ON CONFLICT (header_signature) DO UPDATE SET
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  net_col = EXCLUDED.net_col,
  output_col = EXCLUDED.output_col,
  source = EXCLUDED.source;
