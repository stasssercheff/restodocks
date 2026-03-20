-- Тур страницы при первом посещении зарегистрированного пользователя.
-- Для сотрудников с закрытым доступом — тур показывается после открытия доступа.

CREATE TABLE IF NOT EXISTS public.employee_page_tour_seen (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  page_key TEXT NOT NULL,
  seen_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(employee_id, page_key)
);

CREATE INDEX IF NOT EXISTS idx_employee_page_tour_seen_employee
  ON public.employee_page_tour_seen(employee_id);

ALTER TABLE public.employee_page_tour_seen ENABLE ROW LEVEL SECURITY;

-- Сотрудник видит и вставляет только свои записи (auth_user_id или id для legacy owners)
CREATE POLICY "Employee manages own tour progress"
  ON public.employee_page_tour_seen
  FOR ALL
  USING (
    employee_id IN (
      SELECT id FROM public.employees
      WHERE auth_user_id = auth.uid() OR id = auth.uid()
    )
  )
  WITH CHECK (
    employee_id IN (
      SELECT id FROM public.employees
      WHERE auth_user_id = auth.uid() OR id = auth.uid()
    )
  );
