-- 1) Промокоды: пакеты +5 сотрудников / +1 филиал, режим только аддоны (без смены тарифа).
-- 2) Данные: все строки с grants_subscription_type = pro → ultra (как просили).
-- 3) Снятие UNIQUE(establishment_id) с promo_code_redemptions — чтобы на одно заведение
--    можно было погасить отдельный аддон-код после основного тарифного (разные promo_code_id).

-- Зависимость: если миграция 20260612153000 не применялась — колонки не будет.
ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS grants_subscription_type text NOT NULL DEFAULT 'pro';

COMMENT ON COLUMN public.promo_codes.grants_subscription_type IS
  'Тариф, который выдаёт промокод при применении (pro, ultra, premium, …).';

-- --- Колонки шаблона промокода ---
ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS grants_employee_slot_packs integer NOT NULL DEFAULT 0
    CHECK (grants_employee_slot_packs >= 0 AND grants_employee_slot_packs <= 500);

ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS grants_branch_slot_packs integer NOT NULL DEFAULT 0
    CHECK (grants_branch_slot_packs >= 0 AND grants_branch_slot_packs <= 500);

ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS grants_additive_only boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.promo_codes.grants_employee_slot_packs IS
  'При погашении: +N пакетов по +5 сотрудников (owner_entitlement_addons.employee_slot_packs).';

COMMENT ON COLUMN public.promo_codes.grants_branch_slot_packs IS
  'При погашении: +N дополнительных филиалов (owner_entitlement_addons.branch_slot_packs).';

COMMENT ON COLUMN public.promo_codes.grants_additive_only IS
  'true: только начислить пакеты, не менять subscription_type заведения (аддон после основного промо).';

-- --- Исторические pro в шаблонах → ultra (новые регистрации/применения будут ultra) ---
UPDATE public.promo_codes
SET grants_subscription_type = 'ultra'
WHERE lower(trim(grants_subscription_type)) = 'pro';

-- Опционально: уже созданные заведения с subscription_type = pro (только если уверены, что это не IAP).
-- Раскомментируйте при необходимости:
-- UPDATE public.establishments
-- SET subscription_type = 'ultra', updated_at = now()
-- WHERE lower(trim(COALESCE(subscription_type, ''))) = 'pro'
--   AND (pro_paid_until IS NULL OR pro_paid_until <= now());

-- --- Убрать «одно погашение на заведение» (оставляем UNIQUE (promo_code_id, establishment_id)) ---
ALTER TABLE public.promo_code_redemptions
  DROP CONSTRAINT IF EXISTS promo_code_redemptions_establishment_id_key;

-- Слияние пакетов на владельца (вызывается из RPC после проверок).
CREATE OR REPLACE FUNCTION public.owner_entitlement_merge_addon_packs (
  p_owner_id uuid,
  p_employee_packs integer,
  p_branch_packs integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ve integer := GREATEST(0, COALESCE(p_employee_packs, 0));
  vb integer := GREATEST(0, COALESCE(p_branch_packs, 0));
BEGIN
  IF p_owner_id IS NULL OR (ve = 0 AND vb = 0) THEN
    RETURN;
  END IF;

  INSERT INTO public.owner_entitlement_addons AS o (
    owner_id,
    employee_slot_packs,
    branch_slot_packs,
    updated_at
  )
  VALUES (p_owner_id, ve, vb, now())
  ON CONFLICT (owner_id) DO UPDATE
  SET
    employee_slot_packs = o.employee_slot_packs + EXCLUDED.employee_slot_packs,
    branch_slot_packs = o.branch_slot_packs + EXCLUDED.branch_slot_packs,
    updated_at = now();
END;
$$;

COMMENT ON FUNCTION public.owner_entitlement_merge_addon_packs (uuid, integer, integer) IS
  'Начислить владельцу пакеты +5 сотрудников / +1 филиал (идемпотентное сложение).';

REVOKE ALL ON FUNCTION public.owner_entitlement_merge_addon_packs (uuid, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_entitlement_merge_addon_packs (uuid, integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.apply_promo_to_establishment_for_owner (
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
  v_owner_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT
      1
    FROM
      public.employees e
    WHERE
      e.establishment_id = p_establishment_id
      AND e.auth_user_id = auth.uid()
      AND COALESCE(e.is_active, true)
      AND 'owner' = ANY (e.roles)
  ) THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: owner only';
  END IF;

  SELECT
    owner_id
  INTO v_owner_id
  FROM
    public.establishments
  WHERE
    id = p_establishment_id;

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

  IF v_n >= 1 THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  IF COALESCE(v_row.grants_additive_only, false) THEN
    IF COALESCE(v_row.grants_employee_slot_packs, 0) = 0
       AND COALESCE(v_row.grants_branch_slot_packs, 0) = 0 THEN
      RAISE EXCEPTION 'PROMO_ADDON_EMPTY';
    END IF;
  ELSE
    v_grant := lower(trim(COALESCE(v_row.grants_subscription_type, 'pro')));

    IF NOT public.subscription_type_is_paid_tier(v_grant) THEN
      RAISE EXCEPTION 'PROMO_INVALID_TIER';
    END IF;

    IF EXISTS (
      SELECT
        1
      FROM
        public.promo_code_redemptions r
        INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
      WHERE
        r.establishment_id = p_establishment_id
        AND NOT COALESCE(pc.grants_additive_only, false)
    ) THEN
      RAISE EXCEPTION 'ESTABLISHMENT_HAS_PROMO';
    END IF;
  END IF;

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id)
  VALUES (v_row.id, p_establishment_id);

  PERFORM public.owner_entitlement_merge_addon_packs(
    v_owner_id,
    COALESCE(v_row.grants_employee_slot_packs, 0),
    COALESCE(v_row.grants_branch_slot_packs, 0)
  );

  IF COALESCE(v_row.grants_additive_only, false) THEN
    RETURN jsonb_build_object('ok', true, 'additive_only', true);
  END IF;

  v_grant := lower(trim(COALESCE(v_row.grants_subscription_type, 'pro')));

  SELECT
    lower(trim(COALESCE(subscription_type, 'free')))
  INTO v_sub
  FROM
    public.establishments
  WHERE
    id = p_establishment_id;

  UPDATE public.establishments
  SET
    subscription_type = CASE
      WHEN v_sub = 'premium' AND v_grant = 'pro' THEN 'premium'
      ELSE v_grant
    END,
    pro_trial_ends_at = CASE WHEN v_sub = 'premium' THEN pro_trial_ends_at ELSE NULL END,
    updated_at = now()
  WHERE
    id = p_establishment_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.apply_promo_to_establishment_for_owner (uuid, text) IS
  'Промокод: тариф (кроме additive_only) + начисление пакетов; additive_only — только пакеты.';

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

  IF v_n >= 1 THEN
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

  IF auth.uid() IS NOT NULL THEN
    PERFORM public.owner_entitlement_merge_addon_packs(
      auth.uid(),
      COALESCE(v_row.grants_employee_slot_packs, 0),
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
  'Регистрация с промокодом; тариф + пакеты на owner при auth.uid(); additive_only запрещён.';

-- Права (как раньше)
GRANT EXECUTE ON FUNCTION public.apply_promo_to_establishment_for_owner (uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_company_with_promo (text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.register_company_with_promo (text, text, text, text) TO authenticated;

-- Примеры вставки (подставьте свои code / expires_at; не дублируйте code в БД):
--
-- Ultra (как бывший pro):
-- INSERT INTO public.promo_codes (code, expires_at, grants_subscription_type, grants_employee_slot_packs, grants_branch_slot_packs, grants_additive_only)
-- VALUES ('ULTRA-XXXX', '2027-12-31'::date, 'ultra', 0, 0, false);
--
-- Pro:
-- INSERT INTO public.promo_codes (code, expires_at, grants_subscription_type, grants_employee_slot_packs, grants_branch_slot_packs, grants_additive_only)
-- VALUES ('PRO-XXXX', '2027-12-31'::date, 'pro', 0, 0, false);
--
-- Только +5 сотрудников (после того как у заведения уже есть тарифный промо; additive_only):
-- INSERT INTO public.promo_codes (code, expires_at, grants_subscription_type, grants_employee_slot_packs, grants_branch_slot_packs, grants_additive_only)
-- VALUES ('EMP5-XXXX', '2027-12-31'::date, 'pro', 1, 0, true);
--
-- Только +1 филиал:
-- INSERT INTO public.promo_codes (code, expires_at, grants_subscription_type, grants_employee_slot_packs, grants_branch_slot_packs, grants_additive_only)
-- VALUES ('BR1-XXXX', '2027-12-31'::date, 'pro', 0, 1, true);
--
-- Ultra + 2 пакета по сотрудникам (+10 слотов) и 1 филиал в одном коде:
-- INSERT INTO public.promo_codes (code, expires_at, grants_subscription_type, grants_employee_slot_packs, grants_branch_slot_packs, grants_additive_only)
-- VALUES ('FULL-XXXX', '2027-12-31'::date, 'ultra', 2, 1, false);
