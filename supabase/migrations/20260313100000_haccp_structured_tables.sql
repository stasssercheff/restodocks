-- Журналы ХАССП: структурированные таблицы вместо единой JSONB
-- numeric — замеры (t°, влажность, часы), status — чек-листы, quality — бракераж + фритюр

-- 1. Drop old table
DROP TABLE IF EXISTS public.haccp_logs CASCADE;

-- 2. Enum типов (оставляем, используется во всех таблицах)
DO $$ BEGIN
  CREATE TYPE haccp_log_type AS ENUM (
    'health_hygiene', 'uv_lamps', 'pediculosis',
    'fridge_temperature', 'warehouse_temp_humidity', 'dishwasher_control', 'grease_trap_cleaning',
    'finished_product_brakerage', 'incoming_raw_brakerage', 'frying_oil', 'food_waste',
    'glass_ceramics_breakage', 'emergency_incidents', 'disinsection_deratization',
    'general_cleaning_schedule', 'disinfectant_concentration'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 3. haccp_numeric_logs — температура, влажность, часы
CREATE TABLE IF NOT EXISTS public.haccp_numeric_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  log_type haccp_log_type NOT NULL,
  value1 NUMERIC(8, 2) NOT NULL,
  value2 NUMERIC(8, 2),
  equipment TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_haccp_numeric_establishment ON haccp_numeric_logs(establishment_id);
CREATE INDEX idx_haccp_numeric_log_type ON haccp_numeric_logs(log_type);
CREATE INDEX idx_haccp_numeric_est_type_created ON haccp_numeric_logs(establishment_id, log_type, created_at DESC);

ALTER TABLE haccp_numeric_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_haccp_numeric_select" ON haccp_numeric_logs;
DROP POLICY IF EXISTS "auth_haccp_numeric_insert" ON haccp_numeric_logs;
DROP POLICY IF EXISTS "auth_haccp_numeric_delete" ON haccp_numeric_logs;

CREATE POLICY "auth_haccp_numeric_select" ON haccp_numeric_logs FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));

CREATE POLICY "auth_haccp_numeric_insert" ON haccp_numeric_logs FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND created_by_employee_id = auth.uid()
    AND NOT is_current_user_view_only_owner()
  );

CREATE POLICY "auth_haccp_numeric_delete" ON haccp_numeric_logs FOR DELETE TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND NOT is_current_user_view_only_owner()
  );

-- 4. haccp_status_logs — чек-листы (здоровье, уборка, мойка)
CREATE TABLE IF NOT EXISTS public.haccp_status_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  log_type haccp_log_type NOT NULL,
  status_ok BOOLEAN NOT NULL,
  status2_ok BOOLEAN,
  description TEXT,
  location TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_haccp_status_establishment ON haccp_status_logs(establishment_id);
CREATE INDEX idx_haccp_status_log_type ON haccp_status_logs(log_type);
CREATE INDEX idx_haccp_status_est_type_created ON haccp_status_logs(establishment_id, log_type, created_at DESC);

ALTER TABLE haccp_status_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_haccp_status_select" ON haccp_status_logs;
DROP POLICY IF EXISTS "auth_haccp_status_insert" ON haccp_status_logs;
DROP POLICY IF EXISTS "auth_haccp_status_delete" ON haccp_status_logs;

CREATE POLICY "auth_haccp_status_select" ON haccp_status_logs FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));

CREATE POLICY "auth_haccp_status_insert" ON haccp_status_logs FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND created_by_employee_id = auth.uid()
    AND NOT is_current_user_view_only_owner()
  );

CREATE POLICY "auth_haccp_status_delete" ON haccp_status_logs FOR DELETE TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND NOT is_current_user_view_only_owner()
  );

-- 5. haccp_quality_logs — бракераж (связь с ТТК), фритюр, отходы
CREATE TABLE IF NOT EXISTS public.haccp_quality_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  log_type haccp_log_type NOT NULL,
  tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL,
  product_name TEXT,
  result TEXT,
  weight NUMERIC(10, 2),
  reason TEXT,
  action TEXT,
  oil_name TEXT,
  agent TEXT,
  concentration TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_haccp_quality_establishment ON haccp_quality_logs(establishment_id);
CREATE INDEX idx_haccp_quality_log_type ON haccp_quality_logs(log_type);
CREATE INDEX idx_haccp_quality_tech_card ON haccp_quality_logs(tech_card_id);
CREATE INDEX idx_haccp_quality_est_type_created ON haccp_quality_logs(establishment_id, log_type, created_at DESC);

ALTER TABLE haccp_quality_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_haccp_quality_select" ON haccp_quality_logs;
DROP POLICY IF EXISTS "auth_haccp_quality_insert" ON haccp_quality_logs;
DROP POLICY IF EXISTS "auth_haccp_quality_delete" ON haccp_quality_logs;

CREATE POLICY "auth_haccp_quality_select" ON haccp_quality_logs FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));

CREATE POLICY "auth_haccp_quality_insert" ON haccp_quality_logs FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND created_by_employee_id = auth.uid()
    AND NOT is_current_user_view_only_owner()
  );

CREATE POLICY "auth_haccp_quality_delete" ON haccp_quality_logs FOR DELETE TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND NOT is_current_user_view_only_owner()
  );
