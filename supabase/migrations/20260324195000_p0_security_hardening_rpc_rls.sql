-- P0 hardening: tighten RPC execution and tenant authorization checks.
-- Objective: reduce IDOR/cross-tenant risk without changing app feature behavior.

-- 1) save_checklist: authenticated only + tenant ownership check
CREATE OR REPLACE FUNCTION public.save_checklist(
  p_checklist_id uuid,
  p_name text,
  p_updated_at timestamptz,
  p_action_config jsonb,
  p_assigned_department text DEFAULT 'kitchen',
  p_assigned_section text DEFAULT NULL,
  p_assigned_employee_id uuid DEFAULT NULL,
  p_assigned_employee_ids jsonb DEFAULT '[]'::jsonb,
  p_deadline_at timestamptz DEFAULT NULL,
  p_scheduled_for_at timestamptz DEFAULT NULL,
  p_additional_name text DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_idx int := 0;
  v_updated int;
  v_establishment_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'save_checklist: must be authenticated';
  END IF;

  SELECT establishment_id
    INTO v_establishment_id
  FROM checklists
  WHERE id = p_checklist_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'save_checklist: checklist % not found', p_checklist_id;
  END IF;

  IF NOT (v_establishment_id IN (SELECT current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'save_checklist: access denied';
  END IF;

  UPDATE checklists SET
    name = p_name,
    updated_at = p_updated_at,
    action_config = p_action_config,
    assigned_department = COALESCE(NULLIF(trim(p_assigned_department), ''), 'kitchen'),
    assigned_section = p_assigned_section,
    assigned_employee_id = p_assigned_employee_id,
    assigned_employee_ids = p_assigned_employee_ids,
    deadline_at = p_deadline_at,
    scheduled_for_at = p_scheduled_for_at,
    additional_name = p_additional_name,
    type = p_type
  WHERE id = p_checklist_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'save_checklist: checklist % not found', p_checklist_id;
  END IF;

  DELETE FROM checklist_items WHERE checklist_id = p_checklist_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO checklist_items (checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit)
    VALUES (
      p_checklist_id,
      COALESCE(v_item->>'title', ''),
      COALESCE((v_item->>'sort_order')::int, v_idx),
      (NULLIF(trim(v_item->>'tech_card_id'), ''))::uuid,
      (NULLIF(trim(v_item->>'target_quantity'), ''))::numeric,
      NULLIF(trim(v_item->>'target_unit'), '')
    );
    v_idx := v_idx + 1;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.save_checklist(uuid, text, timestamptz, jsonb, text, text, uuid, jsonb, timestamptz, timestamptz, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_checklist(uuid, text, timestamptz, jsonb, text, text, uuid, jsonb, timestamptz, timestamptz, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_checklist(uuid, text, timestamptz, jsonb, text, text, uuid, jsonb, timestamptz, timestamptz, text, text, jsonb) TO authenticated;

-- 2) update_checklist_dates: authenticated only + tenant ownership check
CREATE OR REPLACE FUNCTION public.update_checklist_dates(
  p_checklist_id uuid,
  p_deadline_at timestamptz DEFAULT NULL,
  p_scheduled_for_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_establishment_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'update_checklist_dates: must be authenticated';
  END IF;

  SELECT establishment_id
    INTO v_establishment_id
  FROM checklists
  WHERE id = p_checklist_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'update_checklist_dates: checklist % not found', p_checklist_id;
  END IF;

  IF NOT (v_establishment_id IN (SELECT current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'update_checklist_dates: access denied';
  END IF;

  UPDATE checklists
  SET
    updated_at = now(),
    deadline_at = p_deadline_at,
    scheduled_for_at = p_scheduled_for_at
  WHERE id = p_checklist_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO authenticated;

-- 3) create_owner_employee: caller must be authenticated and equal to target auth user.
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
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'create_owner_employee: must be authenticated';
  END IF;
  IF auth.uid() <> p_auth_user_id THEN
    RAISE EXCEPTION 'create_owner_employee: caller mismatch';
  END IF;
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

REVOKE ALL ON FUNCTION public.create_owner_employee(uuid, uuid, text, text, text, text[], text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_owner_employee(uuid, uuid, text, text, text, text[], text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_owner_employee(uuid, uuid, text, text, text, text[], text) TO authenticated;

-- 4) create_employee_self_register: caller must be authenticated and equal to target auth user.
CREATE OR REPLACE FUNCTION public.create_employee_self_register(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[] DEFAULT ARRAY['employee']
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
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'create_employee_self_register: must be authenticated';
  END IF;
  IF auth.uid() <> p_auth_user_id THEN
    RAISE EXCEPTION 'create_employee_self_register: caller mismatch';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;
  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_self_register: auth user % not found or email mismatch', p_auth_user_id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_employee_self_register: establishment % not found', p_establishment_id;
  END IF;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  INSERT INTO employees (
    id, auth_user_id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, created_at, updated_at
  ) VALUES (
    p_auth_user_id, p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
    nullif(trim(p_section), ''), p_roles, p_establishment_id, v_personal_pin,
    'ru', true, false, v_now, v_now
  );

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles, establishment_id,
           personal_pin, preferred_language, is_active, data_access_enabled, created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;
  RETURN v_emp;
END;
$$;

REVOKE ALL ON FUNCTION public.create_employee_self_register(uuid, uuid, text, text, text, text, text, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_employee_self_register(uuid, uuid, text, text, text, text, text, text[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_employee_self_register(uuid, uuid, text, text, text, text, text, text[]) TO authenticated;

-- 5) establishment_documents RLS: remove open anon/auth FOR ALL policies.
ALTER TABLE establishment_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_establishment_documents" ON establishment_documents;
DROP POLICY IF EXISTS "auth_establishment_documents" ON establishment_documents;
DROP POLICY IF EXISTS "auth_establishment_documents_select" ON establishment_documents;
DROP POLICY IF EXISTS "auth_establishment_documents_insert" ON establishment_documents;
DROP POLICY IF EXISTS "auth_establishment_documents_update" ON establishment_documents;
DROP POLICY IF EXISTS "auth_establishment_documents_delete" ON establishment_documents;

CREATE POLICY "auth_establishment_documents_select"
ON establishment_documents
FOR SELECT
TO authenticated
USING (establishment_id IN (SELECT current_user_establishment_ids()));

CREATE POLICY "auth_establishment_documents_insert"
ON establishment_documents
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
  AND EXISTS (
    SELECT 1
    FROM employees e
    WHERE e.id = auth.uid()
      AND e.establishment_id = establishment_documents.establishment_id
      AND e.is_active = true
      AND (
        e.department = 'management'
        OR e.roles && ARRAY['owner','executive_chef','sous_chef','bar_manager','floor_manager']::text[]
      )
  )
);

CREATE POLICY "auth_establishment_documents_update"
ON establishment_documents
FOR UPDATE
TO authenticated
USING (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
  AND EXISTS (
    SELECT 1
    FROM employees e
    WHERE e.id = auth.uid()
      AND e.establishment_id = establishment_documents.establishment_id
      AND e.is_active = true
      AND (
        e.department = 'management'
        OR e.roles && ARRAY['owner','executive_chef','sous_chef','bar_manager','floor_manager']::text[]
      )
  )
)
WITH CHECK (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
);

CREATE POLICY "auth_establishment_documents_delete"
ON establishment_documents
FOR DELETE
TO authenticated
USING (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
  AND EXISTS (
    SELECT 1
    FROM employees e
    WHERE e.id = auth.uid()
      AND e.establishment_id = establishment_documents.establishment_id
      AND e.is_active = true
      AND (
        e.department = 'management'
        OR e.roles && ARRAY['owner','executive_chef','sous_chef','bar_manager','floor_manager']::text[]
      )
  )
);
