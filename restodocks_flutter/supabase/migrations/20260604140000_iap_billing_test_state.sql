-- Состояние для тестового режима IAP на staging: после успешной оплаты запоминаем время;
-- Edge billing-verify-apple при следующем запросе после N минут сбрасывает Pro и привязку Apple.
-- UUID заведений задаются только в Edge: IAP_BILLING_TEST_ESTABLISHMENT_IDS (не из клиента).

CREATE TABLE IF NOT EXISTS public.iap_billing_test_state (
  establishment_id uuid PRIMARY KEY REFERENCES public.establishments (id) ON DELETE CASCADE,
  last_success_at timestamptz NOT NULL
);

COMMENT ON TABLE public.iap_billing_test_state IS
  'Только staging/beta: таймер авто-сброса тестовой подписки IAP (см. Edge IAP_BILLING_TEST_*).';

ALTER TABLE public.iap_billing_test_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.iap_billing_test_state FROM PUBLIC;
GRANT ALL ON TABLE public.iap_billing_test_state TO service_role;
