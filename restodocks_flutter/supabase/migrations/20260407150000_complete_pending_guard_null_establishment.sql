-- Регрессия от 20260502214000: убрали проверку establishment_id IS NULL.
-- При owner-first (pending без заведения) вызов complete_pending делал INSERT с NULL → 400 от PostgREST.

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
