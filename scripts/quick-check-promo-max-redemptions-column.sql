-- Быстрая проверка: колонка max_redemptions есть после миграции
--   supabase/migrations/20260629120000_promo_max_redemptions.sql
-- Запуск: Supabase → SQL Editor.
-- Ожидание: одна строка, column_name = max_redemptions.

SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'promo_codes'
  AND column_name = 'max_redemptions';
