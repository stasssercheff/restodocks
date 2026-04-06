-- Выполнить в Supabase SQL Editor после успешного применения 20260406200000_owner_first_registration_flow.sql
-- (если эти куски ещё не накатывали отдельно).
--
-- 1) complete_pending_owner_registration — защита от INSERT при establishment_id IS NULL
--    (нужна, если позже применяли 20260502214000 без этой ветки).
-- 2) ensure_owner_first_pending_after_admin_wipe — восстановление pending после удаления заведения в админке.
-- 3) Перезагрузка кэша PostgREST, чтобы RPC сразу были видны клиенту.

-- ─── 20260407150000 (фрагмент: только complete_pending) ─────────────────────
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

-- ─── 20260407140000 ensure_owner_first_pending_after_admin_wipe ──────────────
CREATE OR REPLACE FUNCTION public.ensure_owner_first_pending_after_admin_wipe()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_meta jsonb;
  v_confirmed timestamptz;
  v_lang text := 'ru';
  v_name text;
  v_surname text;
  v_pos text := '';
  v_roles text[] := ARRAY['owner']::text[];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'ensure_owner_first_pending_after_admin_wipe: must be authenticated';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.employees e
    WHERE e.id = v_uid OR e.auth_user_id = v_uid
  ) THEN
    RETURN false;
  END IF;

  IF EXISTS (SELECT 1 FROM public.pending_owner_registrations WHERE auth_user_id = v_uid) THEN
    RETURN false;
  END IF;

  IF EXISTS (SELECT 1 FROM public.establishments WHERE owner_id = v_uid) THEN
    RETURN false;
  END IF;

  SELECT u.email, u.raw_user_meta_data, u.email_confirmed_at
  INTO v_email, v_meta, v_confirmed
  FROM auth.users u
  WHERE u.id = v_uid;

  IF v_email IS NULL OR v_confirmed IS NULL THEN
    RETURN false;
  END IF;

  v_lang := lower(trim(coalesce(v_meta->>'interface_language', 'ru')));
  IF v_lang NOT IN ('ru', 'en', 'es', 'it', 'tr', 'vi') THEN
    v_lang := 'ru';
  END IF;

  v_pos := lower(trim(coalesce(nullif(v_meta->>'position_role', ''), '')));
  IF v_pos = 'owner' THEN
    v_pos := '';
  END IF;

  IF v_pos <> '' THEN
    v_roles := ARRAY['owner', v_pos]::text[];
  END IF;

  v_name := trim(coalesce(v_meta->>'full_name', ''));
  IF v_name = '' THEN
    v_name := split_part(trim(v_email), '@', 1);
  END IF;

  v_surname := nullif(trim(coalesce(v_meta->>'surname', '')), '');

  INSERT INTO public.pending_owner_registrations (
    auth_user_id, establishment_id, full_name, surname, email, roles,
    preferred_language, position_role, created_at, updated_at
  ) VALUES (
    v_uid,
    NULL,
    v_name,
    v_surname,
    trim(v_email),
    v_roles,
    v_lang,
    nullif(v_pos, ''),
    now(),
    now()
  );

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_owner_first_pending_after_admin_wipe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_owner_first_pending_after_admin_wipe() TO authenticated;

COMMENT ON FUNCTION public.ensure_owner_first_pending_after_admin_wipe() IS
  'Восстанавливает pending owner-first после удаления заведения/сотрудников в админке (повторный шаг компании).';

-- ─── PostgREST: обновить кэш схемы (RPC сразу видны из приложения) ────────────
NOTIFY pgrst, 'reload schema';
