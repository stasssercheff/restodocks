-- RPC для создания сотрудника владельцем.
-- Вызывается когда signUp требует подтверждения email — нет сессии нового юзера, вставка через RLS невозможна.
-- Проверяет: caller — owner заведения; auth user создан с совпадающим email.

CREATE OR REPLACE FUNCTION public.create_employee_for_company(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[]
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
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'create_employee_for_company: must be authenticated';
  END IF;

  -- Проверка: caller — owner данного заведения
  SELECT EXISTS (
    SELECT 1 FROM employees e
    WHERE e.id = v_caller_id
      AND e.establishment_id = p_establishment_id
      AND 'owner' = ANY(e.roles)
      AND e.is_active = true
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'create_employee_for_company: only owner can add employees';
  END IF;

  -- Проверка: auth user создан и email совпадает
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;

  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_for_company: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  -- Проверка: establishment существует
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_employee_for_company: establishment % not found', p_establishment_id;
  END IF;

  -- Проверка: email не занят в этом заведении
  IF EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_for_company: email already taken in establishment';
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
    nullif(trim(p_section), ''),
    p_roles, p_establishment_id, v_personal_pin,
    'ru', true, false, v_now, v_now
  );

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.create_employee_for_company IS 'Создание сотрудника владельцем. Вызывается когда signUp требует подтверждения email и RLS не позволяет INSERT.';

GRANT EXECUTE ON FUNCTION public.create_employee_for_company TO authenticated;

-- RPC для самостоятельной регистрации (RegisterScreen): anon, нет сессии после signUp с Confirm Email.
CREATE OR REPLACE FUNCTION public.create_employee_self_register(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_exists boolean;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
BEGIN
  -- Проверка: auth user создан и email совпадает
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;

  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_self_register: auth user not found or email mismatch';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_employee_self_register: establishment not found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_self_register: email already taken';
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
    nullif(trim(p_section), ''),
    p_roles, p_establishment_id, v_personal_pin,
    'ru', true, false, v_now, v_now
  );

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.create_employee_self_register IS 'Самостоятельная регистрация. Вызывается anon после signUp (Confirm Email).';

GRANT EXECUTE ON FUNCTION public.create_employee_self_register TO anon;
GRANT EXECUTE ON FUNCTION public.create_employee_self_register TO authenticated;
