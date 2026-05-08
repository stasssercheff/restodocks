-- Выбранные модификаторы бара/кофе по строке счёта (варианты основы, допы, автокомплименты).
ALTER TABLE public.pos_order_lines
  ADD COLUMN IF NOT EXISTS bar_modifiers jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.pos_order_lines.bar_modifiers IS
  'JSON-массив выбранных модификаторов позиции бара/кофе; может включать stock_delta для списания.';
