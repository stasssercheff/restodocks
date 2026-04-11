-- Бэкфилл для проектов, где не применялась 20260403190000_employee_ui_prefs_and_account_drafts.sql:
-- RPC patch_my_employee_profile ссылается на e.ui_theme / e.ui_view_as_owner → 42703 без этих колонок.
-- Idempotent: безопасно повторять.

ALTER TABLE public.employees
  ADD COLUMN IF NOT EXISTS ui_theme text,
  ADD COLUMN IF NOT EXISTS ui_view_as_owner boolean;

COMMENT ON COLUMN public.employees.ui_theme IS 'Светлая/тёмная тема; сохраняется в учётной записи и совпадает на всех устройствах';
COMMENT ON COLUMN public.employees.ui_view_as_owner IS 'Режим отображения роли (собственник / должность); общая настройка учётной записи на всех устройствах';
