-- Lite / Pro / Ultra: лимиты сотрудников (3 / 8 / 15 + пакеты +5), филиалы через branch_slot_packs,
-- аддоны на владельца. Триал 72 ч — без изменений (кап 20 сотрудников, лимиты trial_increment_usage).

-- Аддоны IAP (пока заполняет service_role / Edge; клиент только читает свою строку).
CREATE TABLE IF NOT EXISTS public.owner_entitlement_addons (
  owner_id uuid NOT NULL PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  employee_slot_packs integer NOT NULL DEFAULT 0 CHECK (
    employee_slot_packs >= 0
    AND employee_slot_packs <= 500
  ),
  branch_slot_packs integer NOT NULL DEFAULT 0 CHECK (
    branch_slot_packs >= 0
    AND branch_slot_packs <= 500
  ),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.owner_entitlement_addons IS
  'Аддоны владельца: employee_slot_packs (+5 сотрудников за единицу), branch_slot_packs (+1 филиал за единицу).';

ALTER TABLE public.owner_entitlement_addons ENABLE ROW LEVEL SECURITY;

CREATE POLICY owner_entitlement_addons_select_own
  ON public.owner_entitlement_addons
  FOR SELECT
  USING (owner_id = auth.uid());

GRANT SELECT ON public.owner_entitlement_addons TO authenticated;
GRANT ALL ON public.owner_entitlement_addons TO service_role;

-- ultra — платный тариф; lite — явный бесплатный (эквивалент free).
CREATE OR REPLACE FUNCTION public.subscription_type_is_paid_tier (p_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(trim(COALESCE(p_type, 'free'))) IN (
    'pro',
    'premium',
    'ultra',
    'plus',
    'starter',
    'business'
  );
$$;

COMMENT ON FUNCTION public.subscription_type_is_paid_tier (text) IS
  'Платный тариф (не free/lite): pro, ultra, premium, …';

CREATE OR REPLACE FUNCTION public.establishment_has_active_paid_pro (p_establishment_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub text;
  v_paid_until timestamptz;
  v_has_promo boolean;
BEGIN
  SELECT
    lower(trim(COALESCE(subscription_type, 'free'))),
    pro_paid_until
  INTO
    v_sub,
    v_paid_until
  FROM public.establishments
  WHERE id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF NOT public.subscription_type_is_paid_tier(v_sub) THEN
    RETURN false;
  END IF;

  IF v_paid_until IS NOT NULL AND v_paid_until > now() THEN
    RETURN true;
  END IF;

  IF v_paid_until IS NULL THEN
    -- бессрочный grant / промо до отключения
    SELECT
      EXISTS (
        SELECT
          1
        FROM
          public.promo_code_redemptions r
          INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
        WHERE
          r.establishment_id = p_establishment_id
          AND NOT COALESCE(pc.is_disabled, false)
          AND (pc.starts_at IS NULL OR pc.starts_at <= now())
          AND (
            (
              pc.activation_duration_days IS NOT NULL
              AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
            )
            OR (
              pc.activation_duration_days IS NULL
              AND pc.expires_at IS NOT NULL
              AND pc.expires_at >= now()
            )
          )
      )
    INTO v_has_promo;

    RETURN COALESCE(v_has_promo, false);
  END IF;

  SELECT
    EXISTS (
      SELECT
        1
      FROM
        public.promo_code_redemptions r
        INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
      WHERE
        r.establishment_id = p_establishment_id
        AND NOT COALESCE(pc.is_disabled, false)
        AND (pc.starts_at IS NULL OR pc.starts_at <= now())
        AND (
          (
            pc.activation_duration_days IS NOT NULL
            AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
          )
          OR (
            pc.activation_duration_days IS NULL
            AND pc.expires_at IS NOT NULL
            AND pc.expires_at >= now()
          )
        )
    )
  INTO v_has_promo;

  RETURN COALESCE(v_has_promo, false);
END;
$$;

COMMENT ON FUNCTION public.establishment_has_active_paid_pro (uuid) IS
  'Активная оплата или промо для платного тарифа (pro/ultra/…).';

CREATE OR REPLACE FUNCTION public.establishment_active_employee_cap (p_establishment_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_trial_end timestamptz;
  v_promo_max integer;
  v_paid boolean;
  v_sub text;
  v_base integer;
  v_packs integer := 0;
BEGIN
  SELECT
    e.owner_id,
    e.pro_trial_ends_at,
    lower(trim(COALESCE(e.subscription_type, 'free')))
  INTO
    v_owner_id,
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
    COALESCE(o.employee_slot_packs, 0)
  INTO v_packs
  FROM
    public.owner_entitlement_addons o
  WHERE
    o.owner_id = v_owner_id;

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
  'Кап сотрудников: триал 20; оплачено 8 (pro) / 15 (ultra,premium) + пакеты; бесплатно после триала 3 + пакеты; промо max_employees переопределяет базу.';

CREATE OR REPLACE FUNCTION public.is_establishment_paid_pro_active (p_establishment_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription_type text;
  v_paid_until timestamptz;
BEGIN
  SELECT
    lower(trim(COALESCE(e.subscription_type, 'free'))),
    e.pro_paid_until
  INTO
    v_subscription_type,
    v_paid_until
  FROM
    public.establishments e
  WHERE
    e.id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF NOT public.subscription_type_is_paid_tier(v_subscription_type) THEN
    RETURN false;
  END IF;

  IF v_paid_until IS NULL THEN
    RETURN true;
  END IF;

  RETURN v_paid_until > now();
END;
$$;

COMMENT ON FUNCTION public.is_establishment_paid_pro_active (uuid) IS
  'Оплаченный тариф (любой платный тип) по subscription_type и pro_paid_until; NULL paid_until = бессрочный grant.';

CREATE OR REPLACE FUNCTION public.add_establishment_for_owner (
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
  v_owner_trial boolean := false;
  v_branch_packs integer := 0;
  v_global_cap int;
BEGIN
  v_owner_id := auth.uid();

  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT
      1
    FROM
      establishments
    WHERE
      owner_id = v_owner_id
  ) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  SELECT
    COUNT(*)::int
  INTO v_current_count
  FROM
    establishments
  WHERE
    owner_id = v_owner_id;

  SELECT
    EXISTS (
      SELECT
        1
      FROM
        public.establishments e
      WHERE
        e.owner_id = v_owner_id
        AND (
          (
            e.pro_paid_until IS NOT NULL
            AND e.pro_paid_until > now()
          )
          OR EXISTS (
            SELECT
              1
            FROM
              public.promo_code_redemptions r
              INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
            WHERE
              r.establishment_id = e.id
              AND NOT COALESCE(pc.is_disabled, false)
              AND (pc.starts_at IS NULL OR pc.starts_at <= now())
              AND (
                (
                  pc.activation_duration_days IS NOT NULL
                  AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
                )
                OR (
                  pc.activation_duration_days IS NULL
                  AND pc.expires_at IS NOT NULL
                  AND pc.expires_at >= now()
                )
              )
          )
        )
    )
  INTO v_has_paid_pro;

  SELECT
    EXISTS (
      SELECT
        1
      FROM
        public.establishments e
      WHERE
        e.owner_id = v_owner_id
        AND e.pro_trial_ends_at IS NOT NULL
        AND e.pro_trial_ends_at > now()
    )
  INTO v_owner_trial;

  SELECT
    COALESCE(o.branch_slot_packs, 0)
  INTO v_branch_packs
  FROM
    public.owner_entitlement_addons o
  WHERE
    o.owner_id = v_owner_id;

  IF NOT FOUND THEN
    v_branch_packs := 0;
  END IF;

  v_global_cap := public.get_effective_max_additional_establishments_for_owner();

  IF v_owner_trial THEN
    v_max := LEAST(2, v_global_cap);
  ELSIF v_has_paid_pro THEN
    -- Минимум 2 доп. филиала для уже оплаченных аккаунтов (как раньше); сверху — branch_slot_packs.
    v_max := LEAST(GREATEST(v_branch_packs, 2), v_global_cap);
  ELSE
    v_max := 0;
  END IF;

  IF (v_current_count - 1) >= v_max THEN
    RAISE EXCEPTION 'add_establishment_for_owner: limit reached, max % additional establishments per owner', v_max;
  END IF;

  IF p_parent_establishment_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT
        1
      FROM
        establishments
      WHERE
        id = p_parent_establishment_id
        AND owner_id = v_owner_id
        AND parent_establishment_id IS NULL
    ) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: parent must be your main establishment';
    END IF;

    v_template_id := p_parent_establishment_id;
  ELSE
    SELECT
      e.id
    INTO v_template_id
    FROM
      establishments e
    WHERE
      e.owner_id = v_owner_id
    ORDER BY
      e.created_at ASC
    LIMIT 1;
  END IF;

  SELECT
    lower(trim(COALESCE(subscription_type, 'free'))),
    pro_trial_ends_at,
    pro_paid_until
  INTO
    v_sub,
    v_trial,
    v_paid
  FROM
    establishments
  WHERE
    id = v_template_id;

  SELECT
    EXISTS (
      SELECT
        1
      FROM
        public.promo_code_redemptions r
        INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
      WHERE
        r.establishment_id = v_template_id
        AND NOT COALESCE(pc.is_disabled, false)
        AND (pc.starts_at IS NULL OR pc.starts_at <= now())
        AND (
          (
            pc.activation_duration_days IS NOT NULL
            AND r.redeemed_at + make_interval(days => pc.activation_duration_days) >= now()
          )
          OR (
            pc.activation_duration_days IS NULL
            AND pc.expires_at IS NOT NULL
            AND pc.expires_at >= now()
          )
        )
    )
  INTO v_template_has_active_promo;

  IF p_pin_code IS NULL OR trim(p_pin_code) = '' THEN
    LOOP
      v_pin := upper(substring(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 6));

      IF NOT EXISTS (
        SELECT
          1
        FROM
          establishments
        WHERE
          pin_code = v_pin
      ) THEN
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_pin := upper(trim(p_pin_code));

    IF EXISTS (
      SELECT
        1
      FROM
        establishments
      WHERE
        pin_code = v_pin
    ) THEN
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
  RETURNING
    id INTO v_new_id;

  SELECT
    to_jsonb(e.*)
  INTO v_est
  FROM
    establishments e
  WHERE
    e.id = v_new_id;

  INSERT INTO public.promo_code_redemptions(promo_code_id, establishment_id, redeemed_at)
  SELECT
    r.promo_code_id,
    v_new_id,
    r.redeemed_at
  FROM
    public.promo_code_redemptions r
  WHERE
    r.establishment_id = v_template_id
    AND (
      SELECT
        COUNT(*)::int
      FROM
        public.promo_code_redemptions c
      WHERE
        c.promo_code_id = r.promo_code_id
    ) < 2
  ON CONFLICT (promo_code_id, establishment_id) DO NOTHING;

  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.add_establishment_for_owner (text, text, text, text, text, uuid) IS
  'Новое заведение: триал — до 2 доп.; оплачено — max(2, branch_slot_packs) в пределах platform cap; иначе 0.';
