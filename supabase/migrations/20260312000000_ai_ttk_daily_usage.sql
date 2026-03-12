-- Лимит парсинга ТТК через ИИ: 3 документа в день на заведение.
-- Шаблонный парсинг (таблица как в Excel) — без ограничений.

CREATE TABLE IF NOT EXISTS public.ai_ttk_daily_usage (
  establishment_id uuid NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  usage_date date NOT NULL DEFAULT current_date,
  ai_parse_count int NOT NULL DEFAULT 0,
  PRIMARY KEY (establishment_id, usage_date)
);

CREATE INDEX IF NOT EXISTS idx_ai_ttk_daily_usage_date ON ai_ttk_daily_usage(usage_date);

COMMENT ON TABLE ai_ttk_daily_usage IS 'Счётчик вызовов AI для парсинга ТТК (PDF/Excel) — лимит 3 в день. Шаблонный парсинг не учитывается.';

ALTER TABLE ai_ttk_daily_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_ai_ttk_usage" ON ai_ttk_daily_usage;
CREATE POLICY "anon_select_ai_ttk_usage" ON ai_ttk_daily_usage FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_ai_ttk_usage" ON ai_ttk_daily_usage;
CREATE POLICY "anon_insert_ai_ttk_usage" ON ai_ttk_daily_usage FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_ai_ttk_usage" ON ai_ttk_daily_usage;
CREATE POLICY "anon_update_ai_ttk_usage" ON ai_ttk_daily_usage FOR UPDATE TO anon USING (true) WITH CHECK (true);
