-- Persist owner position role through pending registration and completion.
-- Колонка position_role; save_pending оставляем совместимым с owner-first
-- (p_establishment_id в конце, DEFAULT NULL) — см. 20260406200000.
-- Не перезаписываем complete_pending_owner_registration: в 20260406200000 уже есть
-- проверка establishment_id IS NULL и метаданные auth.users.

ALTER TABLE public.pending_owner_registrations
  ADD COLUMN IF NOT EXISTS position_role text;

-- Старые сигнатуры (обязательный establishment вторым аргументом или 7-arg) мешают RPC.
DROP FUNCTION IF EXISTS public.save_pending_owner_registration(uuid, uuid, text, text, text, text[], text);
DROP FUNCTION IF EXISTS public.save_pending_owner_registration(uuid, uuid, text, text, text, text[], text, text);

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

REVOKE ALL ON FUNCTION public.save_pending_owner_registration(uuid, text, text, text, text[], text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, text, text, text, text[], text, text, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, text, text, text, text[], text, text, uuid) TO authenticated;
