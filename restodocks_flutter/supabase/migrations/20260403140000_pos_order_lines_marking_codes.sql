-- Коды маркировки (Честный знак Data Matrix, QR и т.д.) по строкам счёта зала — учёт без отправки в ГИС МТ.
ALTER TABLE public.pos_order_lines
  ADD COLUMN IF NOT EXISTS marking_codes text[] NOT NULL DEFAULT '{}'::text[];

COMMENT ON COLUMN public.pos_order_lines.marking_codes IS
  'Сканированные коды маркировки по позиции (для учёта; вывод в ЧЗ/ЕГАИС — отдельно).';
