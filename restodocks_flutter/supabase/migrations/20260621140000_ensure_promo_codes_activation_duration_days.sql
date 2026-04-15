-- Схема отстаёт от функций: check_establishment_access ссылается на promo_codes.activation_duration_days.
-- Idempotent: безопасно, если колонка уже есть (как в 20260609120000).

ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS activation_duration_days integer;

ALTER TABLE public.promo_codes
  DROP CONSTRAINT IF EXISTS promo_codes_activation_duration_days_check;

ALTER TABLE public.promo_codes
  ADD CONSTRAINT promo_codes_activation_duration_days_check
  CHECK (
    activation_duration_days IS NULL
    OR (activation_duration_days >= 1 AND activation_duration_days <= 36500)
  );

COMMENT ON COLUMN public.promo_codes.activation_duration_days IS
  'Optional relative validity: promo remains active N days after redemption (activation).';
