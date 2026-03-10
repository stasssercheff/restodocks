-- История загруженных бланков iiko для выбора при объединении (последние 3 месяца).
-- Storage: establishment_id/versions/{timestamp}.xlsx
-- Без этой таблицы объединение работает через iiko_blank_meta + originalBlankBytes.

CREATE TABLE IF NOT EXISTS public.iiko_blank_versions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  storage_path     TEXT NOT NULL,
  qty_col_index    INT  NOT NULL DEFAULT 5,
  sheet_names      JSONB,
  sheet_qty_cols   JSONB,
  uploaded_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_iiko_blank_versions_est_uploaded
  ON public.iiko_blank_versions(establishment_id, uploaded_at DESC);

ALTER TABLE public.iiko_blank_versions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_iiko_blank_versions_select" ON public.iiko_blank_versions;
CREATE POLICY "anon_iiko_blank_versions_select" ON public.iiko_blank_versions
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_iiko_blank_versions_insert" ON public.iiko_blank_versions;
CREATE POLICY "anon_iiko_blank_versions_insert" ON public.iiko_blank_versions
  FOR INSERT TO anon WITH CHECK (true);
