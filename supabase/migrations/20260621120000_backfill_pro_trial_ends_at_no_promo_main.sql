-- Восстановить pro_trial_ends_at = created_at + 72h для основных заведений без погашения промокода
-- и тарифа free/lite, если дата триала потеряна (после правок / старые данные).
-- Не трогает строки с promo_code_redemptions, филиалы (parent_establishment_id), pro/ultra и т.д.

UPDATE public.establishments e
SET
  pro_trial_ends_at = e.created_at + interval '72 hours',
  updated_at = now()
WHERE
  e.pro_trial_ends_at IS NULL
  AND e.parent_establishment_id IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.promo_code_redemptions r
    WHERE r.establishment_id = e.id
  )
  AND COALESCE(lower(trim(e.subscription_type)), 'free') IN ('free', 'lite');
