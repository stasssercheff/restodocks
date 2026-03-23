-- Расширение product_aliases: алиасы по заведениям + уверенность (подтверждения/отказы)
-- establishment_id NULL = глобальный алиас; иначе — только для заведения.
-- confidence: +1 при подтверждении, -1 при отказе; при конфликтах выбираем выше.

-- 1. Добавляем колонки
ALTER TABLE product_aliases ADD COLUMN IF NOT EXISTS establishment_id uuid REFERENCES establishments(id) ON DELETE CASCADE;
ALTER TABLE product_aliases ADD COLUMN IF NOT EXISTS confidence int NOT NULL DEFAULT 1;
ALTER TABLE product_aliases ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid();

-- 2. Меняем PK: старый (input_name_normalized) → новый (id), уникальность (input_name_normalized, establishment_id)
UPDATE product_aliases SET id = gen_random_uuid() WHERE id IS NULL;
ALTER TABLE product_aliases ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE product_aliases ALTER COLUMN id SET NOT NULL;

ALTER TABLE product_aliases DROP CONSTRAINT IF EXISTS product_aliases_pkey;
ALTER TABLE product_aliases ADD PRIMARY KEY (id);

DROP INDEX IF EXISTS product_aliases_input_name_normalized_est_unique;
CREATE UNIQUE INDEX product_aliases_input_name_normalized_est_unique
  ON product_aliases (input_name_normalized, establishment_id) NULLS NOT DISTINCT;

-- 3. Таблица отказов: пользователь изменил продукт — не предлагать этот маппинг
CREATE TABLE IF NOT EXISTS product_alias_rejections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  input_name_normalized text NOT NULL,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  establishment_id uuid REFERENCES establishments(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_alias_rejections_unique
  ON product_alias_rejections (input_name_normalized, product_id, establishment_id) NULLS NOT DISTINCT;
CREATE INDEX IF NOT EXISTS idx_product_alias_rejections_lookup
  ON product_alias_rejections (input_name_normalized, establishment_id) NULLS NOT DISTINCT;

COMMENT ON TABLE product_alias_rejections IS 'Отказы: пользователь заменил продукт — не предлагать этот маппинг.';
ALTER TABLE product_alias_rejections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_product_alias_rejections" ON product_alias_rejections;
CREATE POLICY "anon_select_product_alias_rejections" ON product_alias_rejections FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_insert_product_alias_rejections" ON product_alias_rejections;
CREATE POLICY "anon_insert_product_alias_rejections" ON product_alias_rejections FOR INSERT TO anon WITH CHECK (true);
