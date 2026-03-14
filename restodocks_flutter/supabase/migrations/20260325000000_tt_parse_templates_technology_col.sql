ALTER TABLE tt_parse_templates ADD COLUMN IF NOT EXISTS technology_col int NOT NULL DEFAULT -1;
COMMENT ON COLUMN tt_parse_templates.technology_col IS 'Индекс колонки «Технология приготовления», -1 если нет';
