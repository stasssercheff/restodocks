-- Учёт фритюрных жиров (Приложение 8 к СанПиН 2.3/2.4.3590-20): дополнительные колонки в haccp_quality_logs
-- Применить в Supabase SQL Editor при необходимости

ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS organoleptic_start TEXT,
  ADD COLUMN IF NOT EXISTS frying_equipment_type TEXT,
  ADD COLUMN IF NOT EXISTS frying_product_type TEXT,
  ADD COLUMN IF NOT EXISTS frying_end_time TEXT,
  ADD COLUMN IF NOT EXISTS organoleptic_end TEXT,
  ADD COLUMN IF NOT EXISTS carry_over_kg NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS utilized_kg NUMERIC(10, 2);
