-- Preserve owner position role when fallback RPC creates employee row.
-- Root cause: fallback inserted ARRAY['owner'] and ignored pending_owner_registrations.

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

  -- Prefer pending owner registration data when available.
  SELECT * INTO v_pending
  FROM pending_owner_registrations
  WHERE auth_user_id = v_auth_id
  LIMIT 1;

  IF FOUND THEN
    v_est_id := v_pending.establishment_id;
    v_name := trim(coalesce(v_pending.full_name, ''));
    v_surname := nullif(trim(coalesce(v_pending.surname, '')), '');
    v_lang := lower(trim(coalesce(nullif(v_pending.preferred_language, ''), 'ru')));
    IF v_lang NOT IN ('ru', 'en', 'es', 'it', 'tr', 'vi') THEN
      v_lang := 'ru';
    END IF;
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
    -- Fallback path for legacy records without pending row.
    SELECT id INTO v_est_id FROM establishments WHERE owner_id = v_auth_id LIMIT 1;
    IF v_est_id IS NULL THEN
      SELECT id INTO v_est_id FROM establishments
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

  -- Pending row is consumed by this fallback path.
  DELETE FROM pending_owner_registrations
  WHERE auth_user_id = v_auth_id;

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active,
           data_access_enabled, owner_access_level, created_at, updated_at
    FROM employees WHERE id = v_auth_id
  ) r;

  RETURN v_emp;
END;
$$;
