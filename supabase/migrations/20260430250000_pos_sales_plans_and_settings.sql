-- POS: планы продаж (кухня/бар) и флаг доступа управления к финансовым колонкам — в БД (web + мобайл), как заказы POS.

CREATE TABLE IF NOT EXISTS public.establishment_sales_settings (
  establishment_id UUID PRIMARY KEY REFERENCES public.establishments (id) ON DELETE CASCADE,
  show_financials_to_management BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.establishment_sales_settings IS 'Отчёты продаж: показывать себестоимость и продажную цену сотрудникам отдела «Управление».';

CREATE TABLE IF NOT EXISTS public.pos_sales_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  department TEXT NOT NULL CHECK (department IN ('kitchen', 'bar')),
  period_kind TEXT NOT NULL,
  period_start TIMESTAMPTZ NOT NULL,
  period_end TIMESTAMPTZ NOT NULL,
  target_cash_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
  lines JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_by UUID REFERENCES public.employees (id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pos_sales_plans_period_order CHECK (period_end >= period_start)
);

CREATE INDEX IF NOT EXISTS idx_pos_sales_plans_establishment_updated
  ON public.pos_sales_plans (establishment_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_pos_sales_plans_establishment_dept
  ON public.pos_sales_plans (establishment_id, department);

COMMENT ON TABLE public.pos_sales_plans IS 'План продаж по подразделению; lines — JSON массив {tech_card_id, dish_name, target_quantity}.';

ALTER TABLE public.establishment_sales_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pos_sales_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auth_establishment_sales_settings_all ON public.establishment_sales_settings;
CREATE POLICY auth_establishment_sales_settings_all ON public.establishment_sales_settings
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

DROP POLICY IF EXISTS auth_pos_sales_plans_all ON public.pos_sales_plans;
CREATE POLICY auth_pos_sales_plans_all ON public.pos_sales_plans
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.establishment_sales_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pos_sales_plans TO authenticated;
