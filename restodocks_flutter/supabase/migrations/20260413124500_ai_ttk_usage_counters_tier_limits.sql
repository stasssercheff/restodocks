-- Лимиты ТТК с ИИ по тарифу:
-- trial (первые 72 ч): 3 всего за окно trial
-- lite: без доступа
-- pro: 15 в месяц
-- ultra: 40 в месяц

CREATE TABLE IF NOT EXISTS public.ai_ttk_usage_counters (
  establishment_id uuid NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  period_type text NOT NULL,
  period_key text NOT NULL,
  ai_parse_count integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (establishment_id, period_type, period_key)
);

CREATE INDEX IF NOT EXISTS ai_ttk_usage_counters_period_idx
  ON public.ai_ttk_usage_counters (period_type, period_key);

COMMENT ON TABLE public.ai_ttk_usage_counters IS
  'Счетчики AI ТТК по периодам: trial_total и month(YYYY-MM).';

ALTER TABLE public.ai_ttk_usage_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_ttk_usage_counters FROM PUBLIC;
GRANT ALL ON TABLE public.ai_ttk_usage_counters TO service_role;
