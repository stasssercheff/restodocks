-- Пакеты +5 сотрудников — на конкретное заведение (не на владельца целиком).
-- Пакеты +филиал остаются на owner_entitlement_addons.branch_slot_packs.
-- Бэкфилл: старые employee_slot_packs с владельца переносятся на «первое по дате создания» заведение (головная точка учёта).

-- 1) Таблица аддонов по заведению
CREATE TABLE IF NOT EXISTS public.establishment_entitlement_addons (
  establishment_id uuid NOT NULL PRIMARY KEY REFERENCES public.establishments (id) ON DELETE CASCADE,
  employee_slot_packs integer NOT NULL DEFAULT 0 CHECK (
    employee_slot_packs >= 0
    AND employee_slot_packs <= 500
  ),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.establishment_entitlement_addons IS
  'Пакеты +5 активных сотрудников на заведение (IAP/промо начисляются на выбранное при покупке / на заведение погашения).';

ALTER TABLE public.establishment_entitlement_addons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS establishment_entitlement_addons_select_own ON public.establishment_entitlement_addons;

CREATE POLICY establishment_entitlement_addons_select_own
  ON public.establishment_entitlement_addons
  FOR SELECT
  USING (
    EXISTS (
      SELECT
        1
      FROM
        public.establishments e
      WHERE
        e.id = establishment_entitlement_addons.establishment_id
        AND e.owner_id = auth.uid()
    )
  );

GRANT SELECT ON public.establishment_entitlement_addons TO authenticated;
GRANT ALL ON public.establishment_entitlement_addons TO service_role;

-- 2) Перенос с owner_entitlement_addons.employee_slot_packs → первое заведение владельца (если колонка ещё есть).
--    Если 151200/161200 не применялись или колонку уже удалили — шаг пропускается.
DO $$
BEGIN
  IF EXISTS (
    SELECT
      1
    FROM
      information_schema.columns
    WHERE
      table_schema = 'public'
      AND table_name = 'owner_entitlement_addons'
      AND column_name = 'employee_slot_packs'
  ) THEN
    INSERT INTO public.establishment_entitlement_addons (establishment_id, employee_slot_packs, updated_at)
    SELECT
      s.first_est_id,
      o.employee_slot_packs,
      now()
    FROM
      public.owner_entitlement_addons o
      INNER JOIN (
        SELECT DISTINCT ON (owner_id)
          owner_id,
          id AS first_est_id
        FROM
          public.establishments
        ORDER BY
          owner_id,
          created_at ASC
      ) s ON s.owner_id = o.owner_id
    WHERE
      COALESCE(o.employee_slot_packs, 0) > 0
    ON CONFLICT (establishment_id) DO UPDATE
    SET
      employee_slot_packs = establishment_entitlement_addons.employee_slot_packs + EXCLUDED.employee_slot_packs,
      updated_at = now();
  END IF;
END
$$;

-- 3) У владельца остаются только пакеты филиалов
ALTER TABLE public.owner_entitlement_addons
  DROP COLUMN IF EXISTS employee_slot_packs;

-- Строка owner_entitlement_addons нужна для branch_slot_packs; создаём пустые, если не было (после DROP employee).
INSERT INTO public.owner_entitlement_addons (owner_id, branch_slot_packs, updated_at)
SELECT DISTINCT
  e.owner_id,
  0,
  now()
FROM
  public.establishments e
WHERE
  NOT EXISTS (
    SELECT
      1
    FROM
      public.owner_entitlement_addons o
    WHERE
      o.owner_id = e.owner_id
  );

-- Несколько заведений у владельца: чтобы лимит доп. филиалов не был ниже уже существующей сетки,
-- поднимаем branch_slot_packs минимум до max(0, N - 3), где N — число заведений (сверх «2 базовых» для оплаченного сценария).
UPDATE public.owner_entitlement_addons o
SET
  branch_slot_packs = GREATEST(
    o.branch_slot_packs,
    GREATEST(0, ec.cnt - 3)
  ),
  updated_at = now()
FROM (
  SELECT
    owner_id,
    COUNT(*)::int AS cnt
  FROM
    public.establishments
  GROUP BY
    owner_id
  HAVING
    COUNT(*) >= 3
) ec
WHERE
  ec.owner_id = o.owner_id;

COMMENT ON TABLE public.owner_entitlement_addons IS
  'Аддоны владельца: branch_slot_packs (+1 слот на доп. заведение/филиал). Пакеты сотрудников — establishment_entitlement_addons.';

COMMENT ON COLUMN public.promo_codes.grants_employee_slot_packs IS
  'При погашении: +N пакетов по +5 сотрудников на это заведение (establishment_entitlement_addons).';

COMMENT ON COLUMN public.promo_codes.grants_branch_slot_packs IS
  'При погашении: +N слотов филиалов на владельца (owner_entitlement_addons.branch_slot_packs).';

DROP FUNCTION IF EXISTS public.owner_entitlement_merge_addon_packs (uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.establishment_entitlement_merge_employee_packs (
  p_establishment_id uuid,
  p_packs integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v integer := GREATEST(0, COALESCE(p_packs, 0));
BEGIN
  IF p_establishment_id IS NULL OR v = 0 THEN
    RETURN;
  END IF;

  INSERT INTO public.establishment_entitlement_addons AS e (
    establishment_id,
    employee_slot_packs,
    updated_at
  )
  VALUES (p_establishment_id, v, now())
  ON CONFLICT (establishment_id) DO UPDATE
  SET
    employee_slot_packs = e.employee_slot_packs + EXCLUDED.employee_slot_packs,
    updated_at = now();
END;
$$;

COMMENT ON FUNCTION public.establishment_entitlement_merge_employee_packs (uuid, integer) IS
  'Начислить пакеты +5 сотрудников на заведение (идемпотентное сложение).';

REVOKE ALL ON FUNCTION public.establishment_entitlement_merge_employee_packs (uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.establishment_entitlement_merge_employee_packs (uuid, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.owner_entitlement_merge_branch_slot_packs (
  p_owner_id uuid,
  p_packs integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v integer := GREATEST(0, COALESCE(p_packs, 0));
BEGIN
  IF p_owner_id IS NULL OR v = 0 THEN
    RETURN;
  END IF;

  INSERT INTO public.owner_entitlement_addons AS o (
    owner_id,
    branch_slot_packs,
    updated_at
  )
  VALUES (p_owner_id, v, now())
  ON CONFLICT (owner_id) DO UPDATE
  SET
    branch_slot_packs = o.branch_slot_packs + EXCLUDED.branch_slot_packs,
    updated_at = now();
END;
$$;

COMMENT ON FUNCTION public.owner_entitlement_merge_branch_slot_packs (uuid, integer) IS
  'Начислить владельцу пакеты +1 филиал (идемпотентное сложение).';

REVOKE ALL ON FUNCTION public.owner_entitlement_merge_branch_slot_packs (uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_entitlement_merge_branch_slot_packs (uuid, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.establishment_active_employee_cap (p_establishment_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trial_end timestamptz;
  v_promo_max integer;
  v_paid boolean;
  v_sub text;
  v_base integer;
  v_packs integer := 0;
BEGIN
  SELECT
    e.pro_trial_ends_at,
    lower(trim(COALESCE(e.subscription_type, 'free')))
  INTO
    v_trial_end,
    v_sub
  FROM
    public.establishments e
  WHERE
    e.id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF v_trial_end IS NOT NULL AND v_trial_end > now() THEN
    RETURN 20;
  END IF;

  SELECT
    COALESCE(x.employee_slot_packs, 0)
  INTO v_packs
  FROM
    public.establishment_entitlement_addons x
  WHERE
    x.establishment_id = p_establishment_id;

  IF NOT FOUND THEN
    v_packs := 0;
  END IF;

  v_paid := public.establishment_has_active_paid_pro(p_establishment_id);

  IF v_paid THEN
    SELECT
      pc.max_employees
    INTO v_promo_max
    FROM
      public.promo_code_redemptions r
      INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
    WHERE
      r.establishment_id = p_establishment_id
    LIMIT 1;

    IF v_promo_max IS NOT NULL THEN
      RETURN v_promo_max + v_packs * 5;
    END IF;

    v_base := CASE
      WHEN v_sub IN ('ultra', 'premium') THEN 15
      WHEN v_sub IN ('pro', 'plus', 'starter', 'business') THEN 8
      ELSE 3
    END;

    RETURN v_base + v_packs * 5;
  END IF;

  RETURN 3 + v_packs * 5;
END;
$$;

COMMENT ON FUNCTION public.establishment_active_employee_cap (uuid) IS
  'Кап сотрудников на заведение: триал 20; оплачено 8 (pro) / 15 (ultra,premium) + пакеты этого заведения; бесплатно 3 + пакеты; промо max_employees переопределяет базу.';

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

  PERFORM public.establishment_entitlement_merge_employee_packs(
    p_establishment_id,
    COALESCE(v_row.grants_employee_slot_packs, 0)
  );
  PERFORM public.owner_entitlement_merge_branch_slot_packs(
    v_owner_id,
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
  'Промокод: тариф (кроме additive_only) + пакеты на заведение / филиалы владельца; additive_only — только пакеты.';

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
  'Регистрация с промокодом; пакеты сотрудников на новое заведение; пакеты филиалов на owner при auth.uid().';

GRANT EXECUTE ON FUNCTION public.apply_promo_to_establishment_for_owner (uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_company_with_promo (text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.register_company_with_promo (text, text, text, text) TO authenticated;
