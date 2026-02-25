-- Персистентные данные заведения: график смен и списки поставщиков.
-- Сохраняются в Supabase, чтобы не терялись при редеплое (раньше были в SharedPreferences/localStorage).

-- График смен (schedule)
CREATE TABLE IF NOT EXISTS establishment_schedule_data (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);

CREATE INDEX IF NOT EXISTS idx_establishment_schedule_data_establishment ON establishment_schedule_data(establishment_id);

ALTER TABLE establishment_schedule_data ENABLE ROW LEVEL SECURITY;

-- Anon-доступ (приложение использует custom auth через employees, без Supabase Auth)
DROP POLICY IF EXISTS "anon_schedule_select" ON establishment_schedule_data;
CREATE POLICY "anon_schedule_select" ON establishment_schedule_data
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_schedule_insert" ON establishment_schedule_data;
CREATE POLICY "anon_schedule_insert" ON establishment_schedule_data
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_schedule_update" ON establishment_schedule_data;
CREATE POLICY "anon_schedule_update" ON establishment_schedule_data
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- Списки поставщиков (order lists)
CREATE TABLE IF NOT EXISTS establishment_order_list_data (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '[]',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);

CREATE INDEX IF NOT EXISTS idx_establishment_order_list_data_establishment ON establishment_order_list_data(establishment_id);

ALTER TABLE establishment_order_list_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_order_list_select" ON establishment_order_list_data;
CREATE POLICY "anon_order_list_select" ON establishment_order_list_data
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_order_list_insert" ON establishment_order_list_data;
CREATE POLICY "anon_order_list_insert" ON establishment_order_list_data
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_order_list_update" ON establishment_order_list_data;
CREATE POLICY "anon_order_list_update" ON establishment_order_list_data
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
