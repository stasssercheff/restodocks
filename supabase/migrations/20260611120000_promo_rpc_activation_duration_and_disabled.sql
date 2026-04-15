-- Дополнение к 20260609120000: RPC учитывают activation_duration_days и is_disabled.
-- get_establishment_promo_for_owner: в UI — дата окончания Pro = redeemed_at + N дней.

CREATE OR REPLACE FUNCTION public.apply_promo_to_establishment_for_owner(
  p_establishment_id uuid,
  p_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.promo_codes%rowtype;
  v_n int;
  v_sub text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.employees e
    WHERE e.establishment_id = p_establishment_id
      AND e.auth_user_id = auth.uid()
      AND COALESCE(e.is_active, true)
      AND 'owner' = ANY (e.roles)
  ) THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: owner only';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.promo_code_redemptions WHERE establishment_id = p_establishment_id
  ) THEN
    RAISE EXCEPTION 'ESTABLISHMENT_HAS_PROMO';
  END IF;

  SELECT * INTO v_row
  FROM public.promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF COALESCE(v_row.is_disabled, false) THEN
    RAISE EXCEPTION 'PROMO_DISABLED';
  END IF;

  SELECT COUNT(*)::int INTO v_n
  FROM public.promo_code_redemptions
  WHERE promo_code_id = v_row.id;

  IF v_n >= 1 THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  -- expires_at: срок ввода кода (и для режима «N дней с активации», и для legacy).
  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id)
  VALUES (v_row.id, p_establishment_id);

  SELECT lower(trim(COALESCE(subscription_type, 'free'))) INTO v_sub
  FROM public.establishments
  WHERE id = p_establishment_id;

  UPDATE public.establishments
  SET
    subscription_type = CASE WHEN v_sub = 'premium' THEN subscription_type ELSE 'pro' END,
    pro_trial_ends_at = CASE WHEN v_sub = 'premium' THEN pro_trial_ends_at ELSE NULL END,
    updated_at = now()
  WHERE id = p_establishment_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.apply_promo_to_establishment_for_owner(uuid, text) IS
  'Владелец применяет промокод; учитывается is_disabled; длина Pro — activation_duration_days (см. check_establishment_access).';

DROP FUNCTION IF EXISTS public.get_establishment_promo_for_owner(uuid);

CREATE FUNCTION public.get_establishment_promo_for_owner(p_establishment_id uuid)
RETURNS TABLE (code text, expires_at timestamptz, is_disabled boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'get_establishment_promo_for_owner: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'get_establishment_promo_for_owner: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.id = p_establishment_id
      AND e.owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'get_establishment_promo_for_owner: owner only';
  END IF;

  RETURN QUERY
  SELECT
    pc.code::text,
    CASE
      WHEN pc.activation_duration_days IS NOT NULL THEN
        r.redeemed_at + make_interval(days => pc.activation_duration_days)
      ELSE
        pc.expires_at
    END AS expires_at,
    COALESCE(pc.is_disabled, false)
  FROM public.promo_code_redemptions r
  INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
  WHERE r.establishment_id = p_establishment_id
  ORDER BY r.redeemed_at DESC, r.id DESC
  LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_establishment_promo_for_owner(uuid) IS
  'Промокод заведения; expires_at — конец Pro (фиксированный или redeemed_at + activation_duration_days).';

REVOKE ALL ON FUNCTION public.get_establishment_promo_for_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO service_role;

-- Регистрация с промокодом: отказ, если код отключён в админке.
CREATE OR REPLACE FUNCTION public.register_company_with_promo(
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
  v_row public.promo_codes%rowtype;
  v_est_id uuid;
  v_est jsonb;
  v_n int;
BEGIN
  SELECT * INTO v_row
  FROM public.promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF COALESCE(v_row.is_disabled, false) THEN
    RAISE EXCEPTION 'PROMO_DISABLED';
  END IF;

  SELECT COUNT(*)::int INTO v_n
  FROM public.promo_code_redemptions
  WHERE promo_code_id = v_row.id;

  IF v_n >= 1 THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    pro_trial_ends_at,
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
    NULL,
    now(),
    now()
  );

  INSERT INTO public.pos_dining_tables (
    establishment_id,
    floor_name,
    room_name,
    table_number,
    sort_order,
    status
  )
  VALUES (
    v_est_id,
    '1',
    'Основной',
    1,
    0,
    'free'
  );

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id)
  VALUES (v_row.id, v_est_id);

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
      pro_trial_ends_at,
      created_at,
      updated_at
    FROM public.establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_with_promo(text, text, text, text) IS
  'Регистрация с промокодом; is_disabled блокирует; длина Pro — activation_duration_days.';

