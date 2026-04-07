-- UI: de / fr добавлены в список языков приложения — те же коды в pending/complete owner flows.

CREATE OR REPLACE FUNCTION public.save_pending_owner_registration(
  p_auth_user_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner']::text[],
  p_preferred_language text DEFAULT 'ru',
  p_position_role text DEFAULT NULL,
  p_establishment_id uuid DEFAULT NULL
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
  IF v_lang NOT IN ('ru', 'en', 'es', 'de', 'fr', 'it', 'tr', 'vi') THEN
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

REVOKE ALL ON FUNCTION public.save_pending_owner_registration(uuid, text, text, text, text[], text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, text, text, text, text[], text, text, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, text, text, text, text[], text, text, uuid) TO authenticated;

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

  v_lang := lower(trim(coalesce(nullif(v_row.preferred_language, ''), 'ru')));
  IF v_lang NOT IN ('ru', 'en', 'es', 'de', 'fr', 'it', 'tr', 'vi') THEN
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

CREATE OR REPLACE FUNCTION public.fix_owner_without_employee(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_id uuid;
  v_est_id uuid;
  v_name text;
  v_surname text;
  v_lang text := 'ru';
  v_roles text[] := ARRAY['owner'];
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
  v_pending record;
  v_meta_pos text;
BEGIN
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'fix_owner_without_employee: must be authenticated';
  END IF;

  IF LOWER(trim(p_email)) <> (SELECT LOWER(email) FROM auth.users WHERE id = v_auth_id) THEN
    RAISE EXCEPTION 'fix_owner_without_employee: email does not match current user';
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = v_auth_id) THEN
    SELECT to_jsonb(r) INTO v_emp FROM (
      SELECT id, full_name, surname, email, department, section, roles,
             establishment_id, personal_pin, preferred_language, is_active,
             created_at, updated_at FROM employees WHERE id = v_auth_id
    ) r;
    RETURN v_emp;
  END IF;

  SELECT lower(trim(coalesce(raw_user_meta_data->>'position_role', '')))
  INTO v_meta_pos
  FROM auth.users
  WHERE id = v_auth_id;
  IF v_meta_pos = 'owner' THEN v_meta_pos := ''; END IF;

  SELECT * INTO v_pending
  FROM pending_owner_registrations
  WHERE auth_user_id = v_auth_id
  LIMIT 1;

  IF FOUND THEN
    v_est_id := v_pending.establishment_id;
    v_name := trim(coalesce(v_pending.full_name, ''));
    v_surname := nullif(trim(coalesce(v_pending.surname, '')), '');
    v_lang := lower(trim(coalesce(nullif(v_pending.preferred_language, ''), 'ru')));
    IF v_lang NOT IN ('ru', 'en', 'es', 'de', 'fr', 'it', 'tr', 'vi') THEN v_lang := 'ru'; END IF;

    IF v_pending.roles IS NOT NULL AND array_length(v_pending.roles, 1) > 0 THEN
      SELECT array_agg(DISTINCT x) INTO v_roles
      FROM (
        SELECT 'owner'::text AS x
        UNION ALL
        SELECT lower(trim(r))::text
        FROM unnest(v_pending.roles) AS r
        WHERE lower(trim(r)) <> 'owner'
      ) t;
    END IF;
  ELSE
    SELECT id INTO v_est_id FROM establishments WHERE owner_id = v_auth_id LIMIT 1;
    IF v_est_id IS NULL THEN
      SELECT id INTO v_est_id
      FROM establishments
      WHERE owner_id IS NULL
      ORDER BY created_at DESC
      LIMIT 1;
    END IF;

    v_name := COALESCE(
      (SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = v_auth_id),
      split_part(trim(p_email), '@', 1)
    );
    v_surname := NULL;
  END IF;

  IF coalesce(array_length(v_roles, 1), 0) = 1
     AND v_roles[1] = 'owner'
     AND coalesce(v_meta_pos, '') <> '' THEN
    v_roles := ARRAY['owner', v_meta_pos]::text[];
  END IF;

  IF v_est_id IS NULL THEN
    RAISE EXCEPTION 'fix_owner_without_employee: no establishment for this owner';
  END IF;

  IF v_name IS NULL OR v_name = '' THEN
    v_name := split_part(trim(p_email), '@', 1);
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, auth_user_id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  ) VALUES (
    v_auth_id, v_auth_id, v_name, v_surname, trim(p_email), NULL,
    'management', NULL, v_roles, v_est_id, v_personal_pin,
    v_lang, true, true, 'full', v_now, v_now
  );

  UPDATE establishments SET owner_id = v_auth_id, updated_at = v_now
  WHERE id = v_est_id AND (owner_id IS NULL OR owner_id = v_auth_id);

  DELETE FROM pending_owner_registrations WHERE auth_user_id = v_auth_id;

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active,
           data_access_enabled, owner_access_level, created_at, updated_at
    FROM employees WHERE id = v_auth_id
  ) r;

  RETURN v_emp;
END;
$$;
