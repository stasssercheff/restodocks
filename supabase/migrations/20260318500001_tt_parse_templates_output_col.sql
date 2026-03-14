-- Добавить output_col в tt_parse_templates если ещё нет (нужно для tt-parse-save-learning)
ALTER TABLE tt_parse_templates ADD COLUMN IF NOT EXISTS output_col int NOT NULL DEFAULT -1;
