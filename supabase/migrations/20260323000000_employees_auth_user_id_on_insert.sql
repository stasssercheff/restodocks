-- При создании сотрудника через RPC — сразу заполнять auth_user_id.
-- Требует колонку employees.auth_user_id. Если колонки нет (схема 20260225180000) — пропустить миграцию.

-- 1. create_owner_employee (последняя версия из 20260309200000)
CREATE OR REPLACE FUNCTION public.create_owner_employee(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner'],
  p_owner_access_level text DEFAULT 'full'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
  v_access text := coalesce(nullif(trim(p_owner_access_level), ''), 'full');
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN v_access := 'full'; END IF;
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_owner_employee: establishment % not found', p_establishment_id;
  END IF;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  INSERT INTO employees (
    id, auth_user_id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  ) VALUES (
    p_auth_user_id, p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    'management', NULL, p_roles, p_establishment_id, v_personal_pin,
    'ru', true, true, v_access, v_now, v_now
  );
  UPDATE establishments SET owner_id = p_auth_user_id, updated_at = v_now WHERE id = p_establishment_id;
  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles, establishment_id,
           personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;
  RETURN v_emp;
END;
$$;

-- 2. complete_pending_owner_registration
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
BEGIN
  IF auth.uid() IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_row FROM pending_owner_registrations WHERE auth_user_id = auth.uid();
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  INSERT INTO employees (
    id, auth_user_id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  ) VALUES (
    auth.uid(), auth.uid(), trim(v_row.full_name), v_row.surname, trim(v_row.email), NULL,
    'management', NULL, v_row.roles, v_row.establishment_id, v_personal_pin,
    'ru', true, true, 'full', v_now, v_now
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

-- 3. create_employee_for_company — добавить auth_user_id в оба INSERT
CREATE OR REPLACE FUNCTION public.create_employee_for_company(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[],
  p_owner_access_level text DEFAULT 'full'
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
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN v_access := 'full'; END IF;
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'create_employee_for_company: must be authenticated'; END IF;
  SELECT EXISTS (
    SELECT 1 FROM establishments e
    WHERE e.id = p_establishment_id
      AND (e.owner_id = v_caller_id
           OR EXISTS (SELECT 1 FROM employees emp WHERE emp.id = v_caller_id AND emp.establishment_id = p_establishment_id AND 'owner' = ANY(emp.roles) AND emp.is_active = true))
  ) INTO v_is_owner;
  IF NOT v_is_owner THEN RAISE EXCEPTION 'create_employee_for_company: only owner can add employees'; END IF;
  IF is_current_user_view_only_owner() THEN RAISE EXCEPTION 'create_employee_for_company: view-only owner cannot add employees'; END IF;
  SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_user_id AND LOWER(email) = LOWER(trim(p_email))) INTO v_auth_exists;
  IF NOT v_auth_exists THEN RAISE EXCEPTION 'create_employee_for_company: auth user % not found or email mismatch', p_auth_user_id; END IF;
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN RAISE EXCEPTION 'create_employee_for_company: establishment % not found', p_establishment_id; END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE establishment_id = p_establishment_id AND LOWER(trim(email)) = LOWER(trim(p_email))) THEN
    RAISE EXCEPTION 'create_employee_for_company: email already taken in establishment';
  END IF;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  IF 'owner' = ANY(p_roles) THEN
    INSERT INTO employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at)
    VALUES (p_auth_user_id, p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''), trim(p_email), NULL, COALESCE(NULLIF(trim(p_department), ''), 'management'), nullif(trim(p_section), ''), p_roles, p_establishment_id, v_personal_pin, 'ru', true, true, v_access, v_now, v_now);
  ELSE
    INSERT INTO employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, created_at, updated_at)
    VALUES (p_auth_user_id, p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''), trim(p_email), NULL, COALESCE(NULLIF(trim(p_department), ''), 'kitchen'), nullif(trim(p_section), ''), p_roles, p_establishment_id, v_personal_pin, 'ru', true, false, v_now, v_now);
  END IF;
  SELECT to_jsonb(r) INTO v_emp FROM (SELECT id, full_name, surname, email, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at FROM employees WHERE id = p_auth_user_id) r;
  RETURN v_emp;
END;
$$;

-- 4. create_co_owner_from_invitation
CREATE OR REPLACE FUNCTION public.create_co_owner_from_invitation(
  p_invitation_token text,
  p_full_name text,
  p_surname text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv record;
  v_access text;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'create_co_owner_from_invitation: must be authenticated'; END IF;
  SELECT inv.*, e.id as est_id, e.name as est_name, e.pin_code as est_pin, e.default_currency as est_currency INTO v_inv
  FROM co_owner_invitations inv JOIN establishments e ON e.id = inv.establishment_id
  WHERE inv.invitation_token = p_invitation_token AND inv.status = 'accepted'
    AND LOWER(inv.invited_email) = LOWER((SELECT email FROM auth.users WHERE id = auth.uid()));
  IF v_inv IS NULL THEN RAISE EXCEPTION 'create_co_owner_from_invitation: invalid or expired invitation'; END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE id = auth.uid()) THEN RAISE EXCEPTION 'create_co_owner_from_invitation: employee already exists'; END IF;
  v_access := CASE WHEN coalesce(v_inv.is_view_only_owner, false) THEN 'view_only' ELSE 'full' END;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  INSERT INTO employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at)
  SELECT auth.uid(), auth.uid(), trim(p_full_name), nullif(trim(p_surname), ''), au.email, NULL, 'management', NULL, ARRAY['owner'], v_inv.establishment_id, v_personal_pin, 'ru', true, true, v_access, v_now, v_now
  FROM auth.users au WHERE au.id = auth.uid();
  SELECT to_jsonb(r) INTO v_emp FROM (SELECT id, full_name, surname, email, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at FROM employees WHERE id = auth.uid()) r;
  RETURN v_emp;
END;
$$;
