-- После удаления заведения в админке удаляются employees; pending с этим establishment_id — тоже.
-- Если регистрация владельца уже была завершена, строка pending уже удалена ранее — остаётся
-- auth.users без сотрудника. Вход показывал «нет записи сотрудника». Восстанавливаем owner-first
-- pending (establishment_id NULL), чтобы снова пройти шаг «компания».

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
