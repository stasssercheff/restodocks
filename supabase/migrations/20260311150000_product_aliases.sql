-- Таблица сохранённых маппингов: «как написали» → product_id
-- Позволяет не вызывать AI при повторном импорте тех же названий

CREATE TABLE IF NOT EXISTS public.product_aliases (
  input_name_normalized text PRIMARY KEY,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_aliases_product_id ON product_aliases(product_id);

COMMENT ON TABLE product_aliases IS 'Сохранённые сопоставления при импорте: input_name_normalized → product_id. Разгружает AI при повторных импортах.';

-- RLS: anon (как products)
ALTER TABLE product_aliases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_product_aliases" ON product_aliases;
CREATE POLICY "anon_select_product_aliases" ON product_aliases
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_product_aliases" ON product_aliases;
CREATE POLICY "anon_insert_product_aliases" ON product_aliases
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_product_aliases" ON product_aliases;
CREATE POLICY "anon_update_product_aliases" ON product_aliases
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
