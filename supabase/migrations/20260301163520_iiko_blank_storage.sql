-- Таблица для хранения метаданных iiko-бланка (путь к файлу в Storage, индекс колонки)
-- Байты самого файла хранятся в Supabase Storage bucket "iiko-blanks"

CREATE TABLE IF NOT EXISTS public.iiko_blank_meta (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  storage_path     TEXT NOT NULL,           -- путь в bucket: {estId}/blank.xlsx
  qty_col_index    INT  NOT NULL DEFAULT 5, -- индекс колонки "Остаток фактический"
  uploaded_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);

ALTER TABLE public.iiko_blank_meta ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_iiko_blank_meta" ON public.iiko_blank_meta
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- Storage bucket создаётся через Dashboard или API, не через SQL.
-- Здесь только регистрируем таблицу метаданных.
