-- RPC для автоматического исправления: auth user есть, employee нет.
-- Вызывается при логине, когда Auth успешен, но employees.id не найден.
-- Создаёт владельца и привязывает к заведению без владельца.

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
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
BEGIN
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'fix_owner_without_employee: must be authenticated';
  END IF;

  IF LOWER(trim(p_email)) != (SELECT LOWER(email) FROM auth.users WHERE id = v_auth_id) THEN
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

  -- Сначала: заведение, где этот user уже owner (employee потерялся, напр. после миграции)
  SELECT id INTO v_est_id FROM establishments WHERE owner_id = v_auth_id LIMIT 1;
  -- Иначе: заведение без владельца
  IF v_est_id IS NULL THEN
    SELECT id INTO v_est_id FROM establishments
    WHERE owner_id IS NULL
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_est_id IS NULL THEN
    RAISE EXCEPTION 'fix_owner_without_employee: no establishment for this owner';
  END IF;

  v_name := COALESCE(
    (SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = v_auth_id),
    split_part(trim(p_email), '@', 1)
  );
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, created_at, updated_at
  ) VALUES (
    v_auth_id, v_name, NULL, trim(p_email), NULL,
    'management', NULL, ARRAY['owner'], v_est_id, v_personal_pin,
    'ru', true, v_now, v_now
  );

  UPDATE establishments SET owner_id = v_auth_id, updated_at = v_now
  WHERE id = v_est_id AND (owner_id IS NULL OR owner_id = v_auth_id);

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active,
           created_at, updated_at FROM employees WHERE id = v_auth_id
  ) r;

  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.fix_owner_without_employee IS 'Создаёт employee для auth user, если его нет. Привязывает к establishment без owner.';

GRANT EXECUTE ON FUNCTION public.fix_owner_without_employee TO authenticated;
