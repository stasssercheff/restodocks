-- Fix promo application for Ultra grants:
-- subscription_type_is_paid_tier must treat ultra/premium as paid tiers.

CREATE OR REPLACE FUNCTION public.subscription_type_is_paid_tier(p_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(COALESCE(p_type, 'free'))) IN (
    'pro', 'premium', 'plus', 'starter', 'business', 'ultra'
  );
$$;

COMMENT ON FUNCTION public.subscription_type_is_paid_tier(text) IS
  'Платный тариф (не free): pro/premium/plus/starter/business/ultra.';
