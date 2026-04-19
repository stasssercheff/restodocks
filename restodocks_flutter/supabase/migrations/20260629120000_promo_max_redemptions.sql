-- Сколько раз один и тот же промокод можно погасить (учётных записей / заведений).
-- По умолчанию 1 — поведение как раньше.

ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS max_redemptions integer NOT NULL DEFAULT 1
    CHECK (max_redemptions >= 1 AND max_redemptions <= 100000);

COMMENT ON COLUMN public.promo_codes.max_redemptions IS
  'Максимум погашений одного кода (разных заведений). При достижении — PROMO_USED.';

CREATE OR REPLACE FUNCTION public.promo_code_redemptions_limit_before()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_max int;
BEGIN
  SELECT COALESCE(pc.max_redemptions, 1) INTO v_max
  FROM public.promo_codes pc
  WHERE pc.id = NEW.promo_code_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF (
    SELECT COUNT(*)::int
    FROM public.promo_code_redemptions
    WHERE promo_code_id = NEW.promo_code_id
  ) >= v_max THEN
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
      (
        SELECT COUNT(*)::int
        FROM public.promo_code_redemptions r
        WHERE r.promo_code_id = pc.id
      ) >= COALESCE(pc.max_redemptions, 1)
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

  IF v_n >= COALESCE(v_row.max_redemptions, 1) THEN
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
  'Владелец применяет промокод; лимит max_redemptions; блокировка только при уже активном промо у заведения.';

CREATE OR REPLACE FUNCTION public.register_company_with_promo (
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
  SELECT
    *
  INTO v_row
  FROM
    public.promo_codes
  WHERE
    upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF COALESCE(v_row.is_disabled, false) THEN
    RAISE EXCEPTION 'PROMO_DISABLED';
  END IF;

  SELECT
    COUNT(*)::int
  INTO v_n
  FROM
    public.promo_code_redemptions
  WHERE
    promo_code_id = v_row.id;

  IF v_n >= COALESCE(v_row.max_redemptions, 1) THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  IF COALESCE(v_row.grants_additive_only, false) THEN
    RAISE EXCEPTION 'PROMO_INVALID';
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

  PERFORM public.establishment_entitlement_merge_employee_packs(
    v_est_id,
    COALESCE(v_row.grants_employee_slot_packs, 0)
  );

  IF auth.uid() IS NOT NULL THEN
    PERFORM public.owner_entitlement_merge_branch_slot_packs(
      auth.uid(),
      COALESCE(v_row.grants_branch_slot_packs, 0)
    );
  END IF;

  SELECT
    to_jsonb(e)
  INTO v_est
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
    FROM
      public.establishments
    WHERE
      id = v_est_id
  ) e;

  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_with_promo (text, text, text, text) IS
  'Регистрация с промокодом; лимит max_redemptions; пакеты сотрудников/филиалов как в 20260618120000.';
