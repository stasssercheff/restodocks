-- Single-use promo codes: one promo code can be redeemed by one establishment only.
-- Keeps existing redemptions, only tightens checks and sync semantics.

CREATE OR REPLACE FUNCTION public.promo_code_redemptions_limit_before()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF (
    SELECT COUNT(*)::int
    FROM public.promo_code_redemptions
    WHERE promo_code_id = NEW.promo_code_id
  ) >= 1 THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.promo_code_redemptions_sync_promo_row()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_pc bigint;
BEGIN
  v_pc := COALESCE(NEW.promo_code_id, OLD.promo_code_id);
  UPDATE public.promo_codes pc
  SET
    is_used = (
      SELECT COUNT(*) >= 1
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    ),
    used_at = (
      SELECT MIN(r.redeemed_at)
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    ),
    used_by_establishment_id = (
      SELECT r.establishment_id
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
      ORDER BY r.redeemed_at ASC
      LIMIT 1
    )
  WHERE pc.id = v_pc;
  RETURN COALESCE(NEW, OLD);
END;
$$;

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
  'Регистрация с промокодом; один код — одно заведение; Pro с первого дня.';

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
  'Владелец применяет админский промокод к заведению; один код — одно заведение.';

-- Re-sync already redeemed promo rows to ensure admin sees "used" after first redemption.
UPDATE public.promo_codes pc
SET
  is_used = (
    SELECT COUNT(*) >= 1
    FROM public.promo_code_redemptions r
    WHERE r.promo_code_id = pc.id
  ),
  used_at = (
    SELECT MIN(r.redeemed_at)
    FROM public.promo_code_redemptions r
    WHERE r.promo_code_id = pc.id
  ),
  used_by_establishment_id = (
    SELECT r.establishment_id
    FROM public.promo_code_redemptions r
    WHERE r.promo_code_id = pc.id
    ORDER BY r.redeemed_at ASC
    LIMIT 1
  );
