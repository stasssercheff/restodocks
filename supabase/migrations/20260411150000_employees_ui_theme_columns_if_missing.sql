-- На части окружений не накатывалась 20260403190000 — колонок ui_theme / ui_view_as_owner нет,
-- RPC patch_my_employee_profile падает с 42703 (column ... does not exist).

ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS ui_theme text,
  ADD COLUMN IF NOT EXISTS ui_view_as_owner boolean;

COMMENT ON COLUMN public.employees.ui_theme IS 'Светлая/тёмная тема; сохраняется в учётной записи и совпадает на всех устройствах';
COMMENT ON COLUMN public.employees.ui_view_as_owner IS 'Режим отображения роли (собственник / должность); общая настройка учётной записи на всех устройствах';
