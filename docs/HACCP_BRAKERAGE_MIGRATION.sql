-- =============================================================================
-- Миграция: дополнительные колонки для журналов бракеража ХАССП
-- (Приложения 4 и 5 СанПиН 2.3/2.4.3590-20)
-- Применить вручную в Supabase SQL Editor или: psql ... -f HACCP_BRAKERAGE_MIGRATION.sql
-- =============================================================================

-- Прил.4: время снятия бракеража, разрешение к реализации, подписи комиссии, взвешивание порций
-- Прил.5: фасовка, изготовитель/поставщик, количество, документ, условия хранения, срок реализации, дата реализации

ALTER TABLE public.haccp_quality_logs
  ADD COLUMN IF NOT EXISTS time_brakerage TEXT,
  ADD COLUMN IF NOT EXISTS approval_to_sell TEXT,
  ADD COLUMN IF NOT EXISTS commission_signatures TEXT,
  ADD COLUMN IF NOT EXISTS weighing_result TEXT,
  ADD COLUMN IF NOT EXISTS packaging TEXT,
  ADD COLUMN IF NOT EXISTS manufacturer_supplier TEXT,
  ADD COLUMN IF NOT EXISTS quantity_kg NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS document_number TEXT,
  ADD COLUMN IF NOT EXISTS storage_conditions TEXT,
  ADD COLUMN IF NOT EXISTS expiry_date TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS date_sold TIMESTAMPTZ;
