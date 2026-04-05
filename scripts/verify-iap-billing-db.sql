-- Проверка наличия таблиц IAP (ожидается 2 строки с exists = true).
SELECT
  to_regclass('public.apple_iap_subscription_claims') IS NOT NULL AS apple_iap_subscription_claims_exists,
  to_regclass('public.iap_billing_test_state') IS NOT NULL AS iap_billing_test_state_exists;
