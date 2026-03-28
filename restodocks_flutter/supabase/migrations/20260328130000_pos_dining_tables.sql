-- Столы зала: этаж и зал задаются текстом (как вводит управляющий); при одном этаже/зале вкладки скрываются в UI.
CREATE TABLE IF NOT EXISTS pos_dining_tables (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  floor_name TEXT,
  room_name TEXT,
  table_number INT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'free' CHECK (status IN ('free', 'occupied', 'bill_requested')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS pos_dining_tables_unique_place
  ON pos_dining_tables (
    establishment_id,
    COALESCE(floor_name, ''),
    COALESCE(room_name, ''),
    table_number
  );

CREATE INDEX IF NOT EXISTS idx_pos_dining_tables_establishment
  ON pos_dining_tables (establishment_id);

COMMENT ON TABLE pos_dining_tables IS 'Столы заведения для зала: группировка по этажу и залу, статус для индикации.';

ALTER TABLE pos_dining_tables ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_dining_tables_all" ON pos_dining_tables;
CREATE POLICY "anon_pos_dining_tables_all" ON pos_dining_tables
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_dining_tables_all" ON pos_dining_tables;
CREATE POLICY "auth_pos_dining_tables_all" ON pos_dining_tables
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
