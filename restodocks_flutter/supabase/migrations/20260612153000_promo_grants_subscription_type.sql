-- Промокод может выдавать не только pro: поле grants_subscription_type (по умолчанию pro — поведение как раньше).

ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS grants_subscription_type text NOT NULL DEFAULT 'pro';

COMMENT ON COLUMN public.promo_codes.grants_subscription_type IS
  'Тариф, который выдаёт промокод при применении (pro, premium, plus, …). Старые строки = pro по умолчанию.';

CREATE OR REPLACE FUNCTION public.subscription_type_is_paid_tier(p_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(COALESCE(p_type, 'free'))) IN (
    'pro', 'premium', 'plus', 'starter', 'business'
  );
$$;

COMMENT ON FUNCTION public.subscription_type_is_paid_tier(text) IS
  'Платный тариф (не free): для check_establishment_access и валидации промокодов.';

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
  v_grant text;
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

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  v_grant := lower(trim(COALESCE(v_row.grants_subscription_type, 'pro')));
  IF NOT public.subscription_type_is_paid_tier(v_grant) THEN
    RAISE EXCEPTION 'PROMO_INVALID_TIER';
  END IF;

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id)
  VALUES (v_row.id, p_establishment_id);

  SELECT lower(trim(COALESCE(subscription_type, 'free'))) INTO v_sub
  FROM public.establishments
  WHERE id = p_establishment_id;

  UPDATE public.establishments
  SET
    subscription_type = CASE
      WHEN v_sub = 'premium' AND v_grant = 'pro' THEN 'premium'
      ELSE v_grant
    END,
    pro_trial_ends_at = CASE WHEN v_sub = 'premium' THEN pro_trial_ends_at ELSE NULL END,
    updated_at = now()
  WHERE id = p_establishment_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.apply_promo_to_establishment_for_owner(uuid, text) IS
  'Владелец применяет промокод; тариф из grants_subscription_type (по умолчанию pro).';

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
  v_grant text;
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

  v_grant := lower(trim(COALESCE(v_row.grants_subscription_type, 'pro')));
  IF NOT public.subscription_type_is_paid_tier(v_grant) THEN
    RAISE EXCEPTION 'PROMO_INVALID_TIER';
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
    v_grant,
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
  'Регистрация с промокодом; тариф из grants_subscription_type.';

CREATE OR REPLACE FUNCTION public.check_establishment_access(p_establishment_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub text;
  v_paid_until timestamptz;
  v_has_active_iap boolean;
  v_has_active_promo boolean;
BEGIN
  DELETE FROM public.promo_code_redemptions r
  USING public.promo_codes pc
  WHERE r.establishment_id = p_establishment_id
    AND r.promo_code_id = pc.id
    AND NOT (
      NOT COALESCE(pc.is_disabled, false)
      AND (pc.starts_at IS NULL OR pc.starts_at <= now())
      AND (
        (
          pc.activation_duration_days IS NOT NULL
          AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
        )
        OR (
          pc.activation_duration_days IS NULL
          AND pc.expires_at >= now()
        )
      )
    );

  SELECT
    lower(trim(COALESCE(subscription_type, 'free'))),
    pro_paid_until
  INTO v_sub, v_paid_until
  FROM public.establishments
  WHERE id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN 'ok';
  END IF;

  v_has_active_iap :=
    v_paid_until IS NOT NULL
    AND v_paid_until > now();

  SELECT EXISTS (
    SELECT 1
    FROM public.promo_code_redemptions r
    INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
    WHERE r.establishment_id = p_establishment_id
      AND NOT COALESCE(pc.is_disabled, false)
      AND (pc.starts_at IS NULL OR pc.starts_at <= now())
      AND (
        (
          pc.activation_duration_days IS NOT NULL
          AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
        )
        OR (
          pc.activation_duration_days IS NULL
          AND pc.expires_at >= now()
        )
      )
  )
  INTO v_has_active_promo;

  IF public.subscription_type_is_paid_tier(v_sub)
     AND NOT v_has_active_iap
     AND NOT v_has_active_promo THEN

    UPDATE public.establishments
    SET
      subscription_type = 'free',
      pro_trial_ends_at = NULL,
      pro_paid_until = NULL,
      updated_at = now()
    WHERE id = p_establishment_id;
  END IF;

  RETURN 'ok';
END;
$$;

COMMENT ON FUNCTION public.check_establishment_access(uuid) IS
  'Снятие платного тарифа при отсутствии IAP и активного промо (любой grants_subscription_type).';

-- Новое заведение по шаблону с активным промо: копировать тариф шаблона (plus/premium/…), а не всегда pro.
CREATE OR REPLACE FUNCTION public.add_establishment_for_owner(
  p_name text,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_pin_code text DEFAULT NULL,
  p_parent_establishment_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_est jsonb;
  v_new_id uuid;
  v_now timestamptz := now();
  v_current_count int;
  v_max int;
  v_template_id uuid;
  v_sub text;
  v_trial timestamptz;
  v_paid timestamptz;
  v_has_paid_pro boolean := false;
  v_template_has_active_promo boolean := false;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  SELECT COUNT(*)::int INTO v_current_count
  FROM establishments WHERE owner_id = v_owner_id;

  SELECT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.owner_id = v_owner_id
      AND (
        (e.pro_paid_until IS NOT NULL AND e.pro_paid_until > now())
        OR EXISTS (
          SELECT 1
          FROM public.promo_code_redemptions r
          INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
          WHERE r.establishment_id = e.id
            AND NOT COALESCE(pc.is_disabled, false)
            AND (pc.starts_at IS NULL OR pc.starts_at <= now())
            AND (
              (
                pc.activation_duration_days IS NOT NULL
                AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
              )
              OR (
                pc.activation_duration_days IS NULL
                AND pc.expires_at >= now()
              )
            )
        )
      )
  ) INTO v_has_paid_pro;

  IF v_has_paid_pro THEN
    v_max := LEAST(2, public.get_effective_max_additional_establishments_for_owner());
  ELSE
    v_max := LEAST(0, public.get_effective_max_additional_establishments_for_owner());
  END IF;

  IF (v_current_count - 1) >= v_max THEN
    RAISE EXCEPTION 'add_establishment_for_owner: limit reached, max % additional establishments per owner', v_max;
  END IF;

  IF p_parent_establishment_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM establishments
      WHERE id = p_parent_establishment_id
        AND owner_id = v_owner_id
        AND parent_establishment_id IS NULL
    ) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: parent must be your main establishment';
    END IF;
    v_template_id := p_parent_establishment_id;
  ELSE
    SELECT e.id INTO v_template_id
    FROM establishments e
    WHERE e.owner_id = v_owner_id
    ORDER BY e.created_at ASC
    LIMIT 1;
  END IF;

  SELECT
    lower(trim(COALESCE(subscription_type, 'free'))),
    pro_trial_ends_at,
    pro_paid_until
  INTO v_sub, v_trial, v_paid
  FROM establishments
  WHERE id = v_template_id;

  SELECT EXISTS (
    SELECT 1
    FROM public.promo_code_redemptions r
    INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
    WHERE r.establishment_id = v_template_id
      AND NOT COALESCE(pc.is_disabled, false)
      AND (pc.starts_at IS NULL OR pc.starts_at <= now())
      AND (
        (
          pc.activation_duration_days IS NOT NULL
          AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
        )
        OR (
          pc.activation_duration_days IS NULL
          AND pc.expires_at >= now()
        )
      )
  ) INTO v_template_has_active_promo;

  IF p_pin_code IS NULL OR trim(p_pin_code) = '' THEN
    LOOP
      v_pin := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));
      IF NOT EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_pin := upper(trim(p_pin_code));
    IF EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: pin_code already exists';
    END IF;
  END IF;

  INSERT INTO establishments (
    name,
    pin_code,
    owner_id,
    address,
    phone,
    email,
    parent_establishment_id,
    subscription_type,
    pro_trial_ends_at,
    pro_paid_until,
    created_at,
    updated_at
  )
  VALUES (
    trim(p_name),
    v_pin,
    v_owner_id,
    nullif(trim(p_address), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    p_parent_establishment_id,
    CASE
      WHEN v_template_has_active_promo THEN COALESCE(NULLIF(v_sub, ''), 'pro')
      ELSE NULLIF(trim(COALESCE(v_sub, '')), '')
    END,
    v_trial,
    v_paid,
    v_now,
    v_now
  )
  RETURNING id INTO v_new_id;

  SELECT to_jsonb(e.*) INTO v_est FROM public.establishments e WHERE e.id = v_new_id;

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id, redeemed_at)
  SELECT r.promo_code_id, v_new_id, r.redeemed_at
  FROM public.promo_code_redemptions r
  WHERE r.establishment_id = v_template_id
    AND (
      SELECT COUNT(*)::int
      FROM public.promo_code_redemptions c
      WHERE c.promo_code_id = r.promo_code_id
    ) < 2
  ON CONFLICT (establishment_id) DO NOTHING;

  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.add_establishment_for_owner(text, text, text, text, text, uuid) IS
  'Add establishment by owner; при активном промо копируется тариф шаблона (grants → уже в subscription_type).';

GRANT EXECUTE ON FUNCTION public.add_establishment_for_owner(text, text, text, text, text, uuid) TO authenticated;
