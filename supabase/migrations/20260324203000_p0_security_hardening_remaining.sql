-- P0 continuation: close remaining high-risk DB gaps with minimal behavior change.

-- 1) Harden pending owner registration against establishment takeover.
-- Keep anon compatibility for pre-confirm flow, but enforce safe constraints.
CREATE OR REPLACE FUNCTION public.save_pending_owner_registration(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner']
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_exists boolean;
  v_owner_id uuid;
  v_emp_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;

  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'save_pending_owner_registration: auth user mismatch';
  END IF;

  SELECT owner_id INTO v_owner_id
  FROM establishments
  WHERE id = p_establishment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'save_pending_owner_registration: establishment not found';
  END IF;

  -- Critical guard: do not allow owner reassignment through pending registration.
  IF v_owner_id IS NOT NULL THEN
    RAISE EXCEPTION 'save_pending_owner_registration: establishment already has owner';
  END IF;

  -- Additional guard: establishment with active employees should not accept owner bootstrap.
  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND is_active = true
  ) INTO v_emp_exists;
  IF v_emp_exists THEN
    RAISE EXCEPTION 'save_pending_owner_registration: establishment already initialized';
  END IF;

  INSERT INTO pending_owner_registrations (
    auth_user_id, establishment_id, full_name, surname, email, roles, created_at, updated_at
  )
  VALUES (
    p_auth_user_id, p_establishment_id, trim(p_full_name), nullif(trim(p_surname), ''), trim(p_email), p_roles, now(), now()
  )
  ON CONFLICT (auth_user_id) DO UPDATE SET
    establishment_id = EXCLUDED.establishment_id,
    full_name = EXCLUDED.full_name,
    surname = EXCLUDED.surname,
    email = EXCLUDED.email,
    roles = EXCLUDED.roles,
    updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.save_pending_owner_registration(uuid, uuid, text, text, text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, uuid, text, text, text, text[]) TO anon;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration(uuid, uuid, text, text, text, text[]) TO authenticated;

-- 2) Tighten co_owner_invitations anonymous policies (token-based minimal surface).
ALTER TABLE co_owner_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_co_owner_invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;

-- Anonymous access only for pending invitations with non-empty token.
CREATE POLICY "anon_select_co_owner_invitations"
ON co_owner_invitations
FOR SELECT
TO anon
USING (
  status = 'pending'
  AND invitation_token IS NOT NULL
  AND invitation_token <> ''
);

-- Anonymous update allowed only on pending invitations and only status transition accepted/declined.
CREATE POLICY "anon_update_co_owner_invitations"
ON co_owner_invitations
FOR UPDATE
TO anon
USING (
  status = 'pending'
  AND invitation_token IS NOT NULL
  AND invitation_token <> ''
)
WITH CHECK (
  status IN ('accepted', 'declined')
);

-- 3) Force strict tenant policies for checklists/checklist_items (remove broad FOR ALL true).
ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_checklists_all" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_all" ON checklists;
DROP POLICY IF EXISTS "anon_checklist_items_all" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_all" ON checklist_items;

DROP POLICY IF EXISTS "auth_checklists_select" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_insert" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_update" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_delete" ON checklists;

DROP POLICY IF EXISTS "auth_checklist_items_select" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_insert" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_update" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_delete" ON checklist_items;

CREATE POLICY "auth_checklists_select"
ON checklists
FOR SELECT
TO authenticated
USING (
  establishment_id IN (SELECT current_user_establishment_ids())
  OR assigned_employee_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(coalesce(assigned_employee_ids, '[]'::jsonb)) AS v(emp_id)
    WHERE v.emp_id::uuid = auth.uid()
  )
);

CREATE POLICY "auth_checklists_insert"
ON checklists
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
);

CREATE POLICY "auth_checklists_update"
ON checklists
FOR UPDATE
TO authenticated
USING (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
)
WITH CHECK (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
);

CREATE POLICY "auth_checklists_delete"
ON checklists
FOR DELETE
TO authenticated
USING (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
);

CREATE POLICY "auth_checklist_items_select"
ON checklist_items
FOR SELECT
TO authenticated
USING (
  checklist_id IN (
    SELECT c.id
    FROM checklists c
    WHERE c.establishment_id IN (SELECT current_user_establishment_ids())
       OR c.assigned_employee_id = auth.uid()
       OR EXISTS (
         SELECT 1
         FROM jsonb_array_elements_text(coalesce(c.assigned_employee_ids, '[]'::jsonb)) AS v(emp_id)
         WHERE v.emp_id::uuid = auth.uid()
       )
  )
);

CREATE POLICY "auth_checklist_items_insert"
ON checklist_items
FOR INSERT
TO authenticated
WITH CHECK (
  checklist_id IN (
    SELECT c.id
    FROM checklists c
    WHERE c.establishment_id IN (SELECT current_user_establishment_ids())
      AND NOT is_current_user_view_only_owner()
  )
);

CREATE POLICY "auth_checklist_items_update"
ON checklist_items
FOR UPDATE
TO authenticated
USING (
  checklist_id IN (
    SELECT c.id
    FROM checklists c
    WHERE c.establishment_id IN (SELECT current_user_establishment_ids())
      AND NOT is_current_user_view_only_owner()
  )
)
WITH CHECK (
  checklist_id IN (
    SELECT c.id
    FROM checklists c
    WHERE c.establishment_id IN (SELECT current_user_establishment_ids())
      AND NOT is_current_user_view_only_owner()
  )
);

CREATE POLICY "auth_checklist_items_delete"
ON checklist_items
FOR DELETE
TO authenticated
USING (
  checklist_id IN (
    SELECT c.id
    FROM checklists c
    WHERE c.establishment_id IN (SELECT current_user_establishment_ids())
      AND NOT is_current_user_view_only_owner()
  )
);
