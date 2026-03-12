-- Добавление шаблонов ТТК в каталог (ручная вставка).
-- output_col нужен для seed — добавляем если ещё нет (миграция 20260312150000)
ALTER TABLE tt_parse_templates ADD COLUMN IF NOT EXISTS output_col int NOT NULL DEFAULT -1;
-- header_signature = ячейки заголовка через "|", trim, lowercase.
-- Колонки: name_col, product_col, gross_col, net_col, waste_col (индексы с 0; -1 если нет).
-- header_row_index — обычно 0 или 1.

-- Пример: формат «печеная свекла» (iiko/Чайка):
-- № | Наименование продукта | Ед. изм. | Брутто в ед. изм. | Вес брутто, кг | Вес нетто или п/ф, кг | Вес готового продукта, кг | Технология
INSERT INTO tt_parse_templates (header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, source)
VALUES (
  '№|наименование продукта|ед. изм.|брутто в ед. изм.|вес брутто, кг|вес нетто или п/ф, кг|вес готового продукта, кг|технология приготовления',
  0, 0, 1, 4, 5, -1, 6, 'excel'
)
ON CONFLICT (header_signature) DO UPDATE SET
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  net_col = EXCLUDED.net_col,
  waste_col = EXCLUDED.waste_col,
  output_col = EXCLUDED.output_col,
  source = EXCLUDED.source;

-- Ниже добавляй свои шаблоны. Скопируй блок и подставь значения:
/*
INSERT INTO tt_parse_templates (header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, source)
VALUES (
  'заголовок1|заголовок2|заголовок3|...',  -- как в файле, через |, lowercase
  0,  -- номер строки заголовка (0 = первая)
  0,  -- колонка названия блюда (часто 0)
  1,  -- колонка продукта/ингредиента (часто 1)
  2,  -- колонка брутто (или -1)
  3,  -- колонка нетто (или -1)
  -1, -- колонка % отхода (или -1)
  'excel'
)
ON CONFLICT (header_signature) DO UPDATE SET
  product_col = EXCLUDED.product_col,
  gross_col = EXCLUDED.gross_col,
  net_col = EXCLUDED.net_col,
  waste_col = EXCLUDED.waste_col;
*/
