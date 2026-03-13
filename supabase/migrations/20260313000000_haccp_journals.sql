-- Журналы и ХАССП: универсальная таблица журналов + настройки заведения
-- СанПиН 2.3/2.4.3590-20, ТР ТС 021/2011, Роспотребнадзор

-- 1. Enum типов журналов
DO $$ BEGIN
  CREATE TYPE haccp_log_type AS ENUM (
    -- Группа А: Санитария и Персонал
    'health_hygiene',
    'uv_lamps',
    'pediculosis',
    -- Группа Б: Оборудование и Склад
    'fridge_temperature',
    'warehouse_temp_humidity',
    'dishwasher_control',
    'grease_trap_cleaning',
    -- Группа В: Качество и Бракераж
    'finished_product_brakerage',
    'incoming_raw_brakerage',
    'frying_oil',
    'food_waste',
    -- Группа Г: HACCP PRO
    'glass_ceramics_breakage',
    'emergency_incidents',
    'disinsection_deratization',
    'general_cleaning_schedule',
    'disinfectant_concentration'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 2. Таблица журналов
CREATE TABLE IF NOT EXISTS public.haccp_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  log_type haccp_log_type NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_haccp_logs_establishment ON haccp_logs(establishment_id);
CREATE INDEX IF NOT EXISTS idx_haccp_logs_log_type ON haccp_logs(log_type);
CREATE INDEX IF NOT EXISTS idx_haccp_logs_created_at ON haccp_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_haccp_logs_est_type_created ON haccp_logs(establishment_id, log_type, created_at DESC);

COMMENT ON TABLE haccp_logs IS 'Журналы ХАССП: единая таблица для всех типов журналов';
COMMENT ON COLUMN haccp_logs.payload IS 'Динамические поля формы (jsonb)';
COMMENT ON COLUMN haccp_logs.created_at IS 'Серверный timestamp — основа электронной подписи';

ALTER TABLE haccp_logs ENABLE ROW LEVEL SECURITY;

-- RLS: доступ сотрудникам своего заведения
CREATE POLICY "auth_haccp_select" ON haccp_logs FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
  );

CREATE POLICY "auth_haccp_insert" ON haccp_logs FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND created_by_employee_id = auth.uid()
  );

CREATE POLICY "auth_haccp_delete" ON haccp_logs FOR DELETE TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
  );

-- 3. Настройки журналов заведения (какие журналы включены)
CREATE TABLE IF NOT EXISTS public.establishment_haccp_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  enabled_log_types TEXT[] NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(establishment_id)
);

CREATE INDEX IF NOT EXISTS idx_establishment_haccp_config_establishment ON establishment_haccp_config(establishment_id);

COMMENT ON TABLE establishment_haccp_config IS 'Настройки: какие журналы ХАССП включены для заведения';
COMMENT ON COLUMN establishment_haccp_config.enabled_log_types IS 'Массив log_type (например health_hygiene, fridge_temperature)';

ALTER TABLE establishment_haccp_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_haccp_config_select" ON establishment_haccp_config FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));

CREATE POLICY "auth_haccp_config_insert" ON establishment_haccp_config FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));

CREATE POLICY "auth_haccp_config_update" ON establishment_haccp_config FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()))
  WITH CHECK (true);
