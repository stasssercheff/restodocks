-- Hotfix: на некоторых проектах не была применена 20260429120000_expenses_pro_enforcement.sql,
-- но register_company_* и клиент уже используют establishments.subscription_type.
ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS subscription_type TEXT;

COMMENT ON COLUMN public.establishments.subscription_type IS 'free | pro | premium — доступ к Pro-функциям';
