-- Регистрация: сначала владелец (pending без заведения), затем первое заведение под auth.uid().

ALTER TABLE public.pending_owner_registrations
  ALTER COLUMN establishment_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.save_pending_owner_registration(
  p_auth_user_id uuid,
  p_establishment_id uuid DEFAULT NULL,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner']::text[],
  p_preferred_language text DEFAULT 'ru',
  p_position_role text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_emp_exists boolean;
  v_lang text;
  v_pos text;
BEGIN
  v_lang := lower(trim(coalesce(nullif(p_preferred_language, ''), 'ru')));
  IF v_lang NOT IN ('ru', 'en', 'es', 'it', 'tr', 'vi') THEN
    v_lang := 'ru';
  END IF;

  v_pos := lower(trim(coalesce(nullif(p_position_role, ''), '')));
  IF v_pos = 'owner' THEN
    v_pos := '';
  END IF;
  IF v_pos = '' THEN
    SELECT lower(trim(r)) INTO v_pos
    FROM unnest(coalesce(p_roles, ARRAY['owner']::text[])) AS r
    WHERE lower(trim(r)) <> 'owner'
    LIMIT 1;
  END IF;

  IF p_establishment_id IS NULL THEN
    INSERT INTO pending_owner_registrations (
      auth_user_id, establishment_id, full_name, surname, email, roles,
      preferred_language, position_role, created_at, updated_at
    )
    VALUES (
      p_auth_user_id,
      NULL,
      trim(p_full_name),
      nullif(trim(p_surname), ''),
      trim(p_email),
      p_roles,
      v_lang,
      nullif(v_pos, ''),
      now(),
      now()
    )
    ON CONFLICT (auth_user_id) DO UPDATE SET
      establishment_id = EXCLUDED.establishment_id,
      full_name = EXCLUDED.full_name,
      surname = EXCLUDED.surname,
      email = EXCLUDED.email,
      roles = EXCLUDED.roles,
      preferred_language = EXCLUDED.preferred_language,
      position_role = EXCLUDED.position_role,
      updated_at = now();
    RETURN;
  END IF;

  SELECT owner_id INTO v_owner_id
  FROM establishments
  WHERE id = p_establishment_id;

  IF v_owner_id IS NULL AND NOT EXISTS (
    SELECT 1 FROM establishments WHERE id = p_establishment_id
  ) THEN
    RAISE EXCEPTION 'save_pending_owner_registration: establishment not found';
  END IF;

  IF v_owner_id IS NOT NULL THEN
    RAISE EXCEPTION 'save_pending_owner_registration: establishment already has owner';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND is_active = true
  ) INTO v_emp_exists;
  IF v_emp_exists THEN
    RAISE EXCEPTION 'save_pending_owner_registration: establishment already initialized';
  END IF;

  INSERT INTO pending_owner_registrations (
    auth_user_id, establishment_id, full_name, surname, email, roles,
    preferred_language, position_role, created_at, updated_at
  )
  VALUES (
    p_auth_user_id,
    p_establishment_id,
    trim(p_full_name),
    nullif(trim(p_surname), ''),
    trim(p_email),
    p_roles,
    v_lang,
    nullif(v_pos, ''),
    now(),
    now()
  )
  ON CONFLICT (auth_user_id) DO UPDATE SET
    establishment_id = EXCLUDED.establishment_id,
    full_name = EXCLUDED.full_name,
    surname = EXCLUDED.surname,
    email = EXCLUDED.email,
    roles = EXCLUDED.roles,
    preferred_language = EXCLUDED.preferred_language,
    position_role = EXCLUDED.position_role,
    updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_pending_owner_registration()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
  v_lang text;
  v_roles text[];
  v_pos text;
  v_meta_pos text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NULL; END IF;

  SELECT * INTO v_row
  FROM pending_owner_registrations
  WHERE auth_user_id = auth.uid();

  IF NOT FOUND THEN RETURN NULL; END IF;

  IF v_row.establishment_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_lang := lower(trim(coalesce(nullif(v_row.preferred_language, ''), 'ru')));
  IF v_lang NOT IN ('ru', 'en', 'es', 'it', 'tr', 'vi') THEN
    v_lang := 'ru';
  END IF;

  v_pos := lower(trim(coalesce(nullif(v_row.position_role, ''), '')));
  IF v_pos = 'owner' THEN v_pos := ''; END IF;

  SELECT lower(trim(coalesce(raw_user_meta_data->>'position_role', '')))
  INTO v_meta_pos
  FROM auth.users
  WHERE id = auth.uid();
  IF v_meta_pos = 'owner' THEN v_meta_pos := ''; END IF;

  v_roles := ARRAY['owner']::text[];
  IF v_pos <> '' THEN
    v_roles := ARRAY['owner', v_pos]::text[];
  ELSIF v_row.roles IS NOT NULL AND array_length(v_row.roles, 1) > 0 THEN
    SELECT array_agg(DISTINCT x) INTO v_roles
    FROM (
      SELECT 'owner'::text AS x
      UNION ALL
      SELECT lower(trim(r))::text
      FROM unnest(v_row.roles) AS r
      WHERE lower(trim(r)) <> 'owner'
    ) t;
  END IF;

  IF coalesce(array_length(v_roles, 1), 0) = 1
     AND v_roles[1] = 'owner'
     AND coalesce(v_meta_pos, '') <> '' THEN
    v_roles := ARRAY['owner', v_meta_pos]::text[];
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, auth_user_id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  ) VALUES (
    auth.uid(), auth.uid(), trim(v_row.full_name), v_row.surname, trim(v_row.email), NULL,
    'management', NULL, v_roles, v_row.establishment_id, v_personal_pin,
    v_lang, true, true, 'full', v_now, v_now
  );

  UPDATE establishments
  SET owner_id = auth.uid(), updated_at = v_now
  WHERE id = v_row.establishment_id;

  DELETE FROM pending_owner_registrations
  WHERE auth_user_id = auth.uid();

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles, establishment_id,
           personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
    FROM employees
    WHERE id = auth.uid()
  ) r;

  RETURN jsonb_build_object(
    'employee', v_emp,
    'establishment', (SELECT to_jsonb(e) FROM establishments e WHERE id = v_row.establishment_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.owner_has_pending_registration_without_company()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM pending_owner_registrations
    WHERE auth_user_id = auth.uid()
      AND establishment_id IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.register_first_establishment_without_promo(
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
  v_est_id uuid;
  v_trial_end timestamptz := now() + interval '72 hours';
  v_out jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'register_first_establishment_without_promo: must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pending_owner_registrations
    WHERE auth_user_id = auth.uid()
      AND establishment_id IS NULL
  ) THEN
    RAISE EXCEPTION 'NO_PENDING_OWNER_WITHOUT_COMPANY';
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'ALREADY_HAS_EMPLOYEE';
  END IF;

  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    owner_id,
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
    auth.uid(),
    'RUB',
    'free',
    v_trial_end,
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

  UPDATE public.pending_owner_registrations
  SET establishment_id = v_est_id, updated_at = now()
  WHERE auth_user_id = auth.uid();

  v_out := complete_pending_owner_registration();
  IF v_out IS NULL THEN
    RAISE EXCEPTION 'register_first_establishment_without_promo: complete_pending_failed';
  END IF;
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_first_establishment_with_promo(
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
  v_n int;
  v_out jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'register_first_establishment_with_promo: must be authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pending_owner_registrations
    WHERE auth_user_id = auth.uid()
      AND establishment_id IS NULL
  ) THEN
    RAISE EXCEPTION 'NO_PENDING_OWNER_WITHOUT_COMPANY';
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'ALREADY_HAS_EMPLOYEE';
  END IF;

  SELECT * INTO v_row FROM public.promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  SELECT COUNT(*)::int INTO v_n
  FROM public.promo_code_redemptions
  WHERE promo_code_id = v_row.id;

  IF v_n >= 2 THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.is_used AND v_n = 0 THEN
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
    owner_id,
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
    auth.uid(),
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

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id, redeemed_at)
  VALUES (v_row.id, v_est_id, now());

  UPDATE public.pending_owner_registrations
  SET establishment_id = v_est_id, updated_at = now()
  WHERE auth_user_id = auth.uid();

  v_out := complete_pending_owner_registration();
  IF v_out IS NULL THEN
    RAISE EXCEPTION 'register_first_establishment_with_promo: complete_pending_failed';
  END IF;
  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.owner_has_pending_registration_without_company() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_has_pending_registration_without_company() TO authenticated;

REVOKE ALL ON FUNCTION public.register_first_establishment_without_promo(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_first_establishment_without_promo(text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.register_first_establishment_with_promo(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_first_establishment_with_promo(text, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.register_first_establishment_without_promo(text, text, text) IS
  'Первое заведение после owner-first pending (сессия auth); затем complete_pending_owner_registration.';
