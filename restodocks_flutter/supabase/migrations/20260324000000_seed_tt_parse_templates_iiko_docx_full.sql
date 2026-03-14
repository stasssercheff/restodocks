-- Вариант 1: полная подпись (8 колонок), technology_col=7
INSERT INTO tt_parse_templates (header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, technology_col, source)
VALUES (
  '№|наименование продукта|ед. изм.|брутто в ед. изм.|вес брутто, кг|вес нетто или п/ф, кг|вес готового продукта, кг|технология приготовления',
  8, 0, 1, 4, 5, -1, 6, 7, 'docx'
)
ON CONFLICT (header_signature) DO UPDATE SET
  header_row_index = EXCLUDED.header_row_index,
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  net_col = EXCLUDED.net_col,
  output_col = EXCLUDED.output_col,
  technology_col = EXCLUDED.technology_col,
  source = EXCLUDED.source;

-- Вариант 2: короткая подпись (6 колонок) — на случай отличий при парсинге
INSERT INTO tt_parse_templates (header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, source)
VALUES (
  '№|наименование продукта|ед. изм.|брутто в ед. изм.|вес брутто, кг|вес нетто или п/ф, кг',
  8, 0, 1, 4, 5, -1, -1, 'docx'
)
ON CONFLICT (header_signature) DO UPDATE SET
  header_row_index = EXCLUDED.header_row_index,
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  net_col = EXCLUDED.net_col,
  source = EXCLUDED.source;

-- Выученная позиция названия блюда: row 0, col 0 («Мясная к пенному» — выше заголовка).
INSERT INTO tt_parse_learned_dish_name (header_signature, dish_name_row_offset, dish_name_col, product_col, gross_col, net_col)
VALUES
  ('№|наименование продукта|ед. изм.|брутто в ед. изм.|вес брутто, кг|вес нетто или п/ф, кг|вес готового продукта, кг|технология приготовления', -8, 0, 1, 4, 5),
  ('№|наименование продукта|ед. изм.|брутто в ед. изм.|вес брутто, кг|вес нетто или п/ф, кг', -8, 0, 1, 4, 5)
ON CONFLICT (header_signature) DO UPDATE SET
  dish_name_row_offset = EXCLUDED.dish_name_row_offset,
  dish_name_col = EXCLUDED.dish_name_col,
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  net_col = EXCLUDED.net_col;
