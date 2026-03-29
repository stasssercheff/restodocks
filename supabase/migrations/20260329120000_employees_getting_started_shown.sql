-- Флаг «Начало работы» (диалог) на сотруднике; клиент шлёт getting_started_shown в update.
-- Дублирует restodocks_flutter/supabase/migrations/20260318070000_employees_getting_started_shown.sql для прод-миграций из корня репо.

ALTER TABLE public.employees
ADD COLUMN IF NOT EXISTS getting_started_shown BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.employees
SET getting_started_shown = TRUE
WHERE getting_started_shown = FALSE;
