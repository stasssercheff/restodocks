-- Одна подписка Apple (original_transaction_id) → одно заведение Restodocks.
-- Проверка в Edge billing-verify-apple; при истечении подписки строка удаляется для этого заведения.

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
