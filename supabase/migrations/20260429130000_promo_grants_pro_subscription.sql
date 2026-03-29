-- Промокод из админки = подписка Pro (establishments.subscription_type).
-- Ретроактивно для уже погашенных кодов и для всех новых регистраций по промокоду.

-- 1. Заведения с привязанным использованным промокодом получают Pro
UPDATE public.establishments e
SET subscription_type = 'pro',
    updated_at = now()
WHERE EXISTS (
  SELECT 1
  FROM public.promo_codes p
  WHERE p.used_by_establishment_id = e.id
    AND p.is_used = true
)
AND COALESCE(lower(trim(e.subscription_type)), 'free') NOT IN ('pro', 'premium');

-- 2. register_company_with_promo: сразу создаём заведение с Pro
CREATE OR REPLACE FUNCTION register_company_with_promo(
  p_code text,
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row promo_codes%rowtype;
  v_est_id uuid;
  v_est jsonb;
BEGIN
  SELECT * INTO v_row FROM promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF v_row.is_used THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  v_est_id := gen_random_uuid();
  INSERT INTO establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'pro',
    now(),
    now()
  );

  UPDATE promo_codes
  SET is_used = true, used_by_establishment_id = v_est_id, used_at = now()
  WHERE id = v_row.id;

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      created_at,
      updated_at
    FROM establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION register_company_with_promo(text, text, text, text) IS
  'Регистрация компании с промокодом; промокод из админки даёт подписку Pro.';
