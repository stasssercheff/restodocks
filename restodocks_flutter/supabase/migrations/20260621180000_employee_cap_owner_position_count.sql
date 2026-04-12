-- ТЗ: в лимит сотрудников входят только строки, «занимающие слот».
-- Собственник без должности (в roles только owner) не учитывается — тогда он не блокирует найм,
-- но и не может «освободить» слот для назначения себе должности при полном лимите (кап считается по факту).
-- check_employee_limit согласован с establishment_active_employee_cap и тем же подсчётом.

CREATE OR REPLACE FUNCTION public.employee_row_counts_toward_cap (p_roles text[])
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT
        1
      FROM
        unnest(COALESCE(p_roles, '{}'::text[])) AS r (val)
      WHERE
        val IS NOT NULL
        AND trim(val) <> ''
        AND lower(trim(val)) <> 'owner'
    );
$$;

COMMENT ON FUNCTION public.employee_row_counts_toward_cap (text[]) IS
  'Сотрудник занимает слот лимита, если в roles есть роль кроме owner (должность). Только owner — не считается.';

CREATE OR REPLACE FUNCTION public.establishment_employees_counted_toward_cap (p_establishment_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COUNT(*)::integer
  FROM
    public.employees e
  WHERE
    e.establishment_id = p_establishment_id
    AND COALESCE(e.is_active, true)
    AND public.employee_row_counts_toward_cap (e.roles);
$$;

COMMENT ON FUNCTION public.establishment_employees_counted_toward_cap (uuid) IS
  'Число активных сотрудников, учитываемых в лимите (см. employee_row_counts_toward_cap).';

REVOKE ALL ON FUNCTION public.establishment_employees_counted_toward_cap (uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.establishment_employees_counted_toward_cap (uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_employee_limit (p_establishment_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cap integer;
  v_count integer;
BEGIN
  IF p_establishment_id IS NULL THEN
    RETURN 'ok';
  END IF;

  v_cap := public.establishment_active_employee_cap (p_establishment_id);
  v_count := public.establishment_employees_counted_toward_cap (p_establishment_id);

  IF v_count >= v_cap THEN
    RETURN 'limit_reached';
  END IF;

  RETURN 'ok';
END;
$$;

COMMENT ON FUNCTION public.check_employee_limit (uuid) IS
  'Проверка лимита сотрудников: cap из establishment_active_employee_cap, счёт без owner-only.';

DROP FUNCTION IF EXISTS public.create_employee_for_company (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text
);

CREATE OR REPLACE FUNCTION public.create_employee_for_company (
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[],
  p_owner_access_level text DEFAULT 'full',
  p_birthday date DEFAULT NULL
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
  v_access text := coalesce(nullif(trim(p_owner_access_level), ''), 'full');
  v_count int;
  v_cap int;
  v_new int;
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN
    v_access := 'full';
  END IF;
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'create_employee_for_company: must be authenticated';
  END IF;
  SELECT
    EXISTS (
      SELECT
        1
      FROM
        establishments e
      WHERE
        e.id = p_establishment_id
        AND (
          e.owner_id = v_caller_id
          OR EXISTS (
            SELECT
              1
            FROM
              employees emp
            WHERE
              emp.id = v_caller_id
              AND emp.establishment_id = p_establishment_id
              AND 'owner' = ANY (emp.roles)
              AND COALESCE(emp.is_active, true)
          )
        )
    )
  INTO v_is_owner;
  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'create_employee_for_company: only owner can add employees';
  END IF;
  IF is_current_user_view_only_owner () THEN
    RAISE EXCEPTION 'create_employee_for_company: view-only owner cannot add employees';
  END IF;
  SELECT
    EXISTS (
      SELECT
        1
      FROM
        auth.users
      WHERE
        id = p_auth_user_id
        AND LOWER(email) = LOWER(trim(p_email))
    )
  INTO v_auth_exists;
  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_for_company: auth user % not found or email mismatch', p_auth_user_id;
  END IF;
  IF NOT EXISTS (
    SELECT
      1
    FROM
      establishments
    WHERE
      id = p_establishment_id
  ) THEN
    RAISE EXCEPTION 'create_employee_for_company: establishment % not found', p_establishment_id;
  END IF;
  IF EXISTS (
    SELECT
      1
    FROM
      employees
    WHERE
      establishment_id = p_establishment_id
      AND LOWER(trim(email)) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_for_company: email already taken in establishment';
  END IF;

  v_count := public.establishment_employees_counted_toward_cap (p_establishment_id);
  v_cap := public.establishment_active_employee_cap (p_establishment_id);
  v_new := CASE WHEN public.employee_row_counts_toward_cap (p_roles) THEN
    1
  ELSE
    0
  END;
  IF (v_count + v_new) > v_cap THEN
    RAISE EXCEPTION 'create_employee_for_company: employee_limit_reached cap %', v_cap;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  IF 'owner' = ANY (p_roles) THEN
    INSERT INTO employees (
      id,
      auth_user_id,
      full_name,
      surname,
      email,
      password_hash,
      department,
      section,
      roles,
      establishment_id,
      personal_pin,
      preferred_language,
      is_active,
      data_access_enabled,
      owner_access_level,
      birthday,
      created_at,
      updated_at
    )
    VALUES (
      p_auth_user_id,
      p_auth_user_id,
      trim(p_full_name),
      nullif(trim(p_surname), ''),
      trim(p_email),
      NULL,
      COALESCE(NULLIF(trim(p_department), ''), 'management'),
      nullif(trim(p_section), ''),
      p_roles,
      p_establishment_id,
      v_personal_pin,
      'ru',
      true,
      true,
      v_access,
      p_birthday,
      v_now,
      v_now
    );
  ELSE
    INSERT INTO employees (
      id,
      auth_user_id,
      full_name,
      surname,
      email,
      password_hash,
      department,
      section,
      roles,
      establishment_id,
      personal_pin,
      preferred_language,
      is_active,
      data_access_enabled,
      birthday,
      created_at,
      updated_at
    )
    VALUES (
      p_auth_user_id,
      p_auth_user_id,
      trim(p_full_name),
      nullif(trim(p_surname), ''),
      trim(p_email),
      NULL,
      COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
      nullif(trim(p_section), ''),
      p_roles,
      p_establishment_id,
      v_personal_pin,
      'ru',
      true,
      false,
      p_birthday,
      v_now,
      v_now
    );
  END IF;
  SELECT
    to_jsonb(r) INTO v_emp
  FROM (
    SELECT
      id,
      full_name,
      surname,
      email,
      department,
      section,
      roles,
      establishment_id,
      personal_pin,
      preferred_language,
      is_active,
      data_access_enabled,
      owner_access_level,
      birthday,
      created_at,
      updated_at
    FROM
      employees
    WHERE
      id = p_auth_user_id
  ) r;
  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.create_employee_for_company (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text,
  date
) IS
  'Создание сотрудника владельцем; лимит по establishment_active_employee_cap, owner без должности не в счёте.';

REVOKE ALL ON FUNCTION public.create_employee_for_company (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text,
  date
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_employee_for_company (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  text,
  date
) TO authenticated;

DROP FUNCTION IF EXISTS public.create_employee_self_register (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[]
);

CREATE OR REPLACE FUNCTION public.create_employee_self_register (
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[],
  p_birthday date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp jsonb;
  v_personal_pin text;
  v_auth_exists boolean;
  v_now timestamptz := now();
  v_count int;
  v_cap int;
  v_new int;
BEGIN
  IF auth.uid () IS NULL THEN
    RAISE EXCEPTION 'create_employee_self_register: must be authenticated';
  END IF;
  IF auth.uid () <> p_auth_user_id THEN
    RAISE EXCEPTION 'create_employee_self_register: caller mismatch';
  END IF;
  SELECT
    EXISTS (
      SELECT
        1
      FROM
        auth.users
      WHERE
        id = p_auth_user_id
        AND LOWER(email) = LOWER(trim(p_email))
    )
  INTO v_auth_exists;
  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_self_register: auth user % not found or email mismatch', p_auth_user_id;
  END IF;
  IF NOT EXISTS (
    SELECT
      1
    FROM
      establishments
    WHERE
      id = p_establishment_id
  ) THEN
    RAISE EXCEPTION 'create_employee_self_register: establishment % not found', p_establishment_id;
  END IF;
  IF EXISTS (
    SELECT
      1
      FROM
        employees
      WHERE
        establishment_id = p_establishment_id
        AND LOWER(trim(email)) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_self_register: email already taken';
  END IF;

  v_count := public.establishment_employees_counted_toward_cap (p_establishment_id);
  v_cap := public.establishment_active_employee_cap (p_establishment_id);
  v_new := CASE WHEN public.employee_row_counts_toward_cap (p_roles) THEN
    1
  ELSE
    0
  END;
  IF (v_count + v_new) > v_cap THEN
    RAISE EXCEPTION 'create_employee_self_register: employee_limit_reached cap %', v_cap;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  INSERT INTO employees (
    id,
    auth_user_id,
    full_name,
    surname,
    email,
    password_hash,
    department,
    section,
    roles,
    establishment_id,
    personal_pin,
    preferred_language,
    is_active,
    data_access_enabled,
    birthday,
    created_at,
    updated_at
  )
  VALUES (
    p_auth_user_id,
    p_auth_user_id,
    trim(p_full_name),
    nullif(trim(p_surname), ''),
    trim(p_email),
    NULL,
    COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
    nullif(trim(p_section), ''),
    p_roles,
    p_establishment_id,
    v_personal_pin,
    'ru',
    true,
    false,
    p_birthday,
    v_now,
    v_now
  );

  SELECT
    to_jsonb(r) INTO v_emp
  FROM (
    SELECT
      id,
      full_name,
      surname,
      email,
      department,
      section,
      roles,
      establishment_id,
      personal_pin,
      preferred_language,
      is_active,
      data_access_enabled,
      birthday,
      created_at,
      updated_at
    FROM
      employees
    WHERE
      id = p_auth_user_id
  ) r;
  RETURN v_emp;
END;
$$;

REVOKE ALL ON FUNCTION public.create_employee_self_register (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  date
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_employee_self_register (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  date
) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_employee_self_register (
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text[],
  date
) TO authenticated;

NOTIFY pgrst, 'reload schema';
