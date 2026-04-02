-- Persist owner position role through pending registration and completion.
-- This makes owner position deterministic after email confirmation.

ALTER TABLE public.pending_owner_registrations
  ADD COLUMN IF NOT EXISTS position_role text;

CREATE OR REPLACE FUNCTION public.save_pending_owner_registration(
  p_auth_user_id uuid,
  p_establishment_id uuid,
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
BEGIN
  IF auth.uid() IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_row FROM pending_owner_registrations WHERE auth_user_id = auth.uid();
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_lang := lower(trim(coalesce(nullif(v_row.preferred_language, ''), 'ru')));
  IF v_lang NOT IN ('ru', 'en', 'es', 'it', 'tr', 'vi') THEN
    v_lang := 'ru';
  END IF;

  v_pos := lower(trim(coalesce(nullif(v_row.position_role, ''), '')));
  IF v_pos = 'owner' THEN
    v_pos := '';
  END IF;

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
  UPDATE establishments SET owner_id = auth.uid(), updated_at = v_now WHERE id = v_row.establishment_id;
  DELETE FROM pending_owner_registrations WHERE auth_user_id = auth.uid();
  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles, establishment_id,
           personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
    FROM employees WHERE id = auth.uid()
  ) r;
  RETURN jsonb_build_object('employee', v_emp, 'establishment', (SELECT to_jsonb(e) FROM establishments e WHERE id = v_row.establishment_id));
END;
$$;

REVOKE ALL ON FUNCTION public.save_pending_owner_registration(uuid, uuid, text, text, text, text[], text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, uuid, text, text, text, text[], text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, uuid, text, text, text, text[], text, text) TO authenticated;
