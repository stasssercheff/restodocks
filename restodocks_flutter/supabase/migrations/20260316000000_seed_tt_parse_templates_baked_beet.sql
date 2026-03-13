-- Шаблон для «печенная свекла.xls» (iiko/1С): короткий заголовок без «вес нетто», «выход», «технология».
-- Тест: parseTtkByTemplate iiko/1С с пустой колонкой № empty Наименование
INSERT INTO tt_parse_templates (header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, source)
VALUES (
  '№|наименование продукта|ед. изм.|брутто в ед. изм.|вес брутто, кг',
  3, 0, 2, 9, -1, -1, -1, 'xls'
)
ON CONFLICT (header_signature) DO UPDATE SET
  header_row_index = EXCLUDED.header_row_index,
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  source = EXCLUDED.source;
