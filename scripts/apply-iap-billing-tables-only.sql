-- =============================================================================
-- Только таблицы для Edge billing-verify-apple (если полный supabase db push недоступен).
-- Выполнить в Supabase → SQL Editor проекта osglfptwbuqqmqunttha (или вашего beta).
-- Идемпотентно: CREATE TABLE IF NOT EXISTS.
-- После создания примените миграцию 20260604150000_apple_iap_subscription_claims_owner_id.sql
-- если таблица уже была со столбцом establishment_id (старый формат).
-- =============================================================================

-- Одна подписка Apple (original_transaction_id) → один владелец; Pro на всех его заведениях.
CREATE TABLE IF NOT EXISTS public.apple_iap_subscription_claims (
  original_transaction_id text NOT NULL PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT apple_iap_subscription_claims_owner_unique UNIQUE (owner_id)
);

COMMENT ON TABLE public.apple_iap_subscription_claims IS
  'Привязка auto-renewable IAP Apple к владельцу (owner_id): Pro на всех заведениях этого owner_id.';

CREATE INDEX IF NOT EXISTS apple_iap_subscription_claims_owner_id_idx
  ON public.apple_iap_subscription_claims (owner_id);

ALTER TABLE public.apple_iap_subscription_claims ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.apple_iap_subscription_claims FROM PUBLIC;
GRANT ALL ON TABLE public.apple_iap_subscription_claims TO service_role;

-- Тестовый режим IAP (staging): таймер сброса после успешной верификации.
CREATE TABLE IF NOT EXISTS public.iap_billing_test_state (
  establishment_id uuid PRIMARY KEY REFERENCES public.establishments (id) ON DELETE CASCADE,
  last_success_at timestamptz NOT NULL
);

COMMENT ON TABLE public.iap_billing_test_state IS
  'Только staging/beta: таймер авто-сброса тестовой подписки IAP (см. Edge IAP_BILLING_TEST_*).';

ALTER TABLE public.iap_billing_test_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.iap_billing_test_state FROM PUBLIC;
GRANT ALL ON TABLE public.iap_billing_test_state TO service_role;
