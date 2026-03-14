-- Проверка и применение iiko-шаблона (Технологическая карта.docx)
-- Выполнить в Supabase SQL Editor

-- 1. Добавить technology_col если нет
ALTER TABLE tt_parse_templates ADD COLUMN IF NOT EXISTS technology_col int NOT NULL DEFAULT -1;

-- 2. Проверить текущие шаблоны
SELECT header_signature, header_row_index, product_col, gross_col, net_col, output_col, 
       COALESCE(technology_col, -1) as technology_col
FROM tt_parse_templates 
WHERE header_signature LIKE '%наименование продукта%'
   OR header_signature LIKE '%вес брутто%';

-- 3. Убедиться что iiko-шаблон с правильными колонками
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
