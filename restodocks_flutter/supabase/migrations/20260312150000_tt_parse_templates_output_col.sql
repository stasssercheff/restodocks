-- Добавить колонку «выход» (вес готового продукта) в шаблоны ТТК
ALTER TABLE tt_parse_templates ADD COLUMN IF NOT EXISTS output_col int NOT NULL DEFAULT -1;
COMMENT ON COLUMN tt_parse_templates.output_col IS 'Индекс колонки «Вес готового продукта» / «Выход», -1 если нет';
