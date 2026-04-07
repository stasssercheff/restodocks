-- ТЗ: лимиты сотрудников (free ≤3; trial / оплаченный Pro ≤20 или max_employees промокода)
-- и заведений (без Pro — одно; с Pro — до 3: 1 основное + 2 доп.)

CREATE OR REPLACE FUNCTION public.establishment_has_active_paid_pro(p_establishment_id uuid)
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
  SELECT lower(trim(COALESCE(subscription_type, 'free'))), pro_paid_until
  INTO v_sub, v_paid_until
  FROM public.establishments
  WHERE id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_sub NOT IN ('pro', 'premium') THEN
    RETURN false;
  END IF;

  IF v_paid_until IS NOT NULL AND v_paid_until > now() THEN
    RETURN true;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.promo_code_redemptions r
    INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
    WHERE r.establishment_id = p_establishment_id
      AND NOT COALESCE(pc.is_disabled, false)
      AND (pc.starts_at IS NULL OR pc.starts_at <= now())
      AND (pc.expires_at IS NULL OR pc.expires_at >= now())
  )
  INTO v_has_promo;

  RETURN COALESCE(v_has_promo, false);
END;
$$;

COMMENT ON FUNCTION public.establishment_has_active_paid_pro(uuid) IS
  'Pro по IAP (pro_paid_until) или действующему промокоду; согласовано с check_establishment_access.';

CREATE OR REPLACE FUNCTION public.owner_has_paid_pro_entitlement(p_owner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.owner_id = p_owner_id
      AND public.establishment_has_active_paid_pro(e.id)
  );
$$;

COMMENT ON FUNCTION public.owner_has_paid_pro_entitlement(uuid) IS
  'Хотя бы одно заведение владельца с активным оплаченным Pro (IAP или промо).';

CREATE OR REPLACE FUNCTION public.establishment_active_employee_cap(p_establishment_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trial_end timestamptz;
  v_promo_max integer;
BEGIN
  IF public.establishment_has_active_paid_pro(p_establishment_id) THEN
    SELECT pc.max_employees
    INTO v_promo_max
    FROM public.promo_code_redemptions r
    INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
    WHERE r.establishment_id = p_establishment_id
    LIMIT 1;

    RETURN COALESCE(v_promo_max, 20);
  END IF;

  SELECT pro_trial_ends_at
  INTO v_trial_end
  FROM public.establishments
  WHERE id = p_establishment_id;

  IF v_trial_end IS NOT NULL AND v_trial_end > now() THEN
    RETURN 20;
  END IF;

  RETURN 3;
END;
$$;

COMMENT ON FUNCTION public.establishment_active_employee_cap(uuid) IS
  'Макс. активных сотрудников на заведение: 3 (free после триала), 20 (триал или Pro), или promo.max_employees.';

GRANT EXECUTE ON FUNCTION public.establishment_has_active_paid_pro(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.owner_has_paid_pro_entitlement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.establishment_active_employee_cap(uuid) TO authenticated;

-- Счётчики триала (инвентаризация с выгрузкой, импорт ТТК) — для RPC и клиента
CREATE TABLE IF NOT EXISTS public.establishment_trial_usage (
  establishment_id uuid NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  inventory_exports_with_download integer NOT NULL DEFAULT 0,
  ttk_import_cards integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT establishment_trial_usage_pkey PRIMARY KEY (establishment_id)
);

COMMENT ON TABLE public.establishment_trial_usage IS
  'Лимиты первых 72 ч: выгрузки инвентаризации (3), импорт карточек ТТК (10).';

ALTER TABLE public.establishment_trial_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY establishment_trial_usage_select ON public.establishment_trial_usage
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.establishments e
      WHERE e.id = establishment_trial_usage.establishment_id
        AND (
          e.owner_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.employees emp
            WHERE emp.id = auth.uid()
              AND emp.establishment_id = e.id
              AND emp.is_active = true
          )
        )
    )
  );

CREATE OR REPLACE FUNCTION public.trial_increment_usage(
  p_establishment_id uuid,
  p_kind text,
  p_delta integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trial_end timestamptz;
  v_paid boolean;
  v_inv int;
  v_ttk int;
  v_cap int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'trial_increment_usage: must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.establishments e
    WHERE e.id = p_establishment_id
      AND (
        e.owner_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.employees emp
          WHERE emp.id = auth.uid()
            AND emp.establishment_id = e.id
            AND 'owner' = ANY (emp.roles)
            AND emp.is_active = true
        )
      )
  ) THEN
    RAISE EXCEPTION 'trial_increment_usage: forbidden';
  END IF;

  SELECT pro_trial_ends_at INTO v_trial_end
  FROM public.establishments
  WHERE id = p_establishment_id;

  v_paid := public.establishment_has_active_paid_pro(p_establishment_id);

  IF v_paid OR v_trial_end IS NULL OR v_trial_end <= now() THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true);
  END IF;

  INSERT INTO public.establishment_trial_usage (establishment_id, inventory_exports_with_download, ttk_import_cards)
  VALUES (p_establishment_id, 0, 0)
  ON CONFLICT (establishment_id) DO NOTHING;

  SELECT COALESCE(t.inventory_exports_with_download, 0), COALESCE(t.ttk_import_cards, 0)
  INTO v_inv, v_ttk
  FROM public.establishment_trial_usage t
  WHERE t.establishment_id = p_establishment_id;

  IF lower(trim(p_kind)) = 'inventory_export' THEN
    v_cap := 3;
    IF v_inv + p_delta > v_cap THEN
      RAISE EXCEPTION 'TRIAL_INVENTORY_EXPORT_CAP';
    END IF;
    UPDATE public.establishment_trial_usage
    SET
      inventory_exports_with_download = v_inv + p_delta,
      updated_at = now()
    WHERE establishment_id = p_establishment_id
    RETURNING inventory_exports_with_download, ttk_import_cards INTO v_inv, v_ttk;
  ELSIF lower(trim(p_kind)) = 'ttk_import_cards' THEN
    v_cap := 10;
    IF v_ttk + p_delta > v_cap THEN
      RAISE EXCEPTION 'TRIAL_TTK_IMPORT_CAP';
    END IF;
    UPDATE public.establishment_trial_usage
    SET
      ttk_import_cards = v_ttk + p_delta,
      updated_at = now()
    WHERE establishment_id = p_establishment_id
    RETURNING inventory_exports_with_download, ttk_import_cards INTO v_inv, v_ttk;
  ELSE
    RAISE EXCEPTION 'trial_increment_usage: unknown kind';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'inventory_exports_with_download', v_inv,
    'ttk_import_cards', v_ttk
  );
END;
$$;

COMMENT ON FUNCTION public.trial_increment_usage(uuid, text, integer) IS
  'Увеличить счётчик использования в триале; бросает TRIAL_*_CAP при превышении.';

GRANT EXECUTE ON FUNCTION public.trial_increment_usage(uuid, text, integer) TO authenticated;

-- Лимит сотрудников при создании через RPC
CREATE OR REPLACE FUNCTION public.create_employee_for_company(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[],
  p_owner_access_level text DEFAULT 'full'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_is_owner boolean;
  v_auth_exists boolean;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
  v_access text := coalesce(nullif(trim(p_owner_access_level), ''), 'full');
  v_count int;
  v_cap int;
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN v_access := 'full'; END IF;
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'create_employee_for_company: must be authenticated'; END IF;
  SELECT EXISTS (
    SELECT 1 FROM establishments e
    WHERE e.id = p_establishment_id
      AND (e.owner_id = v_caller_id
           OR EXISTS (SELECT 1 FROM employees emp WHERE emp.id = v_caller_id AND emp.establishment_id = p_establishment_id AND 'owner' = ANY(emp.roles) AND emp.is_active = true))
  ) INTO v_is_owner;
  IF NOT v_is_owner THEN RAISE EXCEPTION 'create_employee_for_company: only owner can add employees'; END IF;
  IF is_current_user_view_only_owner() THEN RAISE EXCEPTION 'create_employee_for_company: view-only owner cannot add employees'; END IF;
  SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_user_id AND LOWER(email) = LOWER(trim(p_email))) INTO v_auth_exists;
  IF NOT v_auth_exists THEN RAISE EXCEPTION 'create_employee_for_company: auth user % not found or email mismatch', p_auth_user_id; END IF;
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN RAISE EXCEPTION 'create_employee_for_company: establishment % not found', p_establishment_id; END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE establishment_id = p_establishment_id AND LOWER(trim(email)) = LOWER(trim(p_email))) THEN
    RAISE EXCEPTION 'create_employee_for_company: email already taken in establishment';
  END IF;

  SELECT COUNT(*)::int INTO v_count
  FROM public.employees
  WHERE establishment_id = p_establishment_id AND is_active = true;

  v_cap := public.establishment_active_employee_cap(p_establishment_id);
  IF v_count >= v_cap THEN
    RAISE EXCEPTION 'create_employee_for_company: employee_limit_reached cap %', v_cap;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  IF 'owner' = ANY(p_roles) THEN
    INSERT INTO employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at)
    VALUES (p_auth_user_id, p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''), trim(p_email), NULL, COALESCE(NULLIF(trim(p_department), ''), 'management'), nullif(trim(p_section), ''), p_roles, p_establishment_id, v_personal_pin, 'ru', true, true, v_access, v_now, v_now);
  ELSE
    INSERT INTO employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, created_at, updated_at)
    VALUES (p_auth_user_id, p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''), trim(p_email), NULL, COALESCE(NULLIF(trim(p_department), ''), 'kitchen'), nullif(trim(p_section), ''), p_roles, p_establishment_id, v_personal_pin, 'ru', true, false, v_now, v_now);
  END IF;
  SELECT to_jsonb(r) INTO v_emp FROM (SELECT id, full_name, surname, email, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at FROM employees WHERE id = p_auth_user_id) r;
  RETURN v_emp;
END;
$$;

-- Лимит заведений: без Pro — только первое; с Pro — до 3 (как 1 + 2 доп.)
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
  v_now timestamptz := now();
  v_current_count int;
  v_max int;
  v_min_override int;
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

  IF public.owner_has_paid_pro_entitlement(v_owner_id) THEN
    v_max := 2;
  ELSE
    v_max := 0;
  END IF;

  SELECT MIN(max_additional_establishments_override)::int
  INTO v_min_override
  FROM establishments
  WHERE owner_id = v_owner_id
    AND max_additional_establishments_override IS NOT NULL;

  IF v_min_override IS NOT NULL THEN
    v_max := LEAST(v_max, v_min_override);
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
  END IF;

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

  INSERT INTO establishments (name, pin_code, owner_id, address, phone, email, parent_establishment_id, created_at, updated_at)
  VALUES (
    trim(p_name), v_pin, v_owner_id,
    nullif(trim(p_address), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    p_parent_establishment_id,
    v_now, v_now
  )
  RETURNING to_jsonb(establishments.*) INTO v_est;

  RETURN v_est;
END;
$$;
