-- =============================================================================
-- Только таблицы для Edge billing-verify-apple (если полный supabase db push недоступен).
-- Выполнить в Supabase → SQL Editor проекта osglfptwbuqqmqunttha (или вашего beta).
-- Идемпотентно: CREATE TABLE IF NOT EXISTS.
-- =============================================================================

-- Одна подписка Apple (original_transaction_id) → одно заведение Restodocks.
CREATE TABLE IF NOT EXISTS public.apple_iap_subscription_claims (
  original_transaction_id text NOT NULL PRIMARY KEY,
  establishment_id uuid NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT apple_iap_subscription_claims_establishment_unique UNIQUE (establishment_id)
);

COMMENT ON TABLE public.apple_iap_subscription_claims IS
  'Привязка auto-renewable IAP Apple к заведению: один original_transaction_id не может быть выдан двум заведениям.';

CREATE INDEX IF NOT EXISTS apple_iap_subscription_claims_establishment_id_idx
  ON public.apple_iap_subscription_claims (establishment_id);

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
