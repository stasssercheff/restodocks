-- Если billing-verify-apple падает с 500 ~2 с после вызова (после verifyReceipt),
-- часто виновато: UPDATE establishments не находит колонок pro_paid_until / subscription_type
-- (миграции через CLI не доехали). Выполнить в SQL Editor того же проекта.

ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS subscription_type TEXT;

ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS pro_paid_until TIMESTAMPTZ;

COMMENT ON COLUMN public.establishments.pro_paid_until IS
  'Дата окончания оплаченного Pro. NULL = бессрочный Pro (например, промокод/ручная выдача).';

COMMENT ON COLUMN public.establishments.subscription_type IS
  'free | pro | premium — доступ к Pro-функциям';
