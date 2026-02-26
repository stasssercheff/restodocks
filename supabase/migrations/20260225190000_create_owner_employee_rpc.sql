-- RPC для создания владельца (owner) при регистрации компании.
-- Вызывается без сессии (после signUp, до подтверждения email).
-- Проверяет, что auth_user_id есть в auth.users с совпадающим email — затем вставляет в employees.

CREATE OR REPLACE FUNCTION public.create_owner_employee(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner']
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
BEGIN
  -- Проверка: пользователь создан в auth.users и email совпадает
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_exists;

  IF NOT v_exists THEN
    RAISE EXCEPTION 'create_owner_employee: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  -- Проверка: establishment существует
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_owner_employee: establishment % not found', p_establishment_id;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    'management', NULL, p_roles, p_establishment_id, v_personal_pin,
    'ru', true, true, v_now, v_now
  );

  UPDATE establishments SET owner_id = p_auth_user_id, updated_at = v_now
  WHERE id = p_establishment_id;

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

COMMENT ON FUNCTION public.create_owner_employee IS 'Создание записи владельца в employees после signUp. Вызывается без сессии (Confirm Email).';

-- Разрешить вызов anon и authenticated
GRANT EXECUTE ON FUNCTION public.create_owner_employee TO anon;
GRANT EXECUTE ON FUNCTION public.create_owner_employee TO authenticated;
