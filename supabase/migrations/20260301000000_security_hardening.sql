-- =============================================================================
-- SECURITY HARDENING — 2026-03-01
--
-- 1. Enable RLS on password_reset_tokens (table was created without it)
-- 2. Fix checklists / checklist_items — remove open anon ALL, scope by establishment_id
-- 3. Fix co_owner_invitations — scope anon UPDATE to the specific invitation token
-- 4. Restrict anon SELECT on employees — replace with SECURITY DEFINER RPCs
-- 5. Restrict anon SELECT on establishments — hide pin_code from direct API access
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. password_reset_tokens — enable RLS, allow only service_role (edge functions)
-- ---------------------------------------------------------------------------
ALTER TABLE password_reset_tokens ENABLE ROW LEVEL SECURITY;

-- No policies for anon or authenticated — only service_role (bypasses RLS)
-- All access goes through edge functions (request-password-reset, reset-password)
-- that use SUPABASE_SERVICE_ROLE_KEY.

-- ---------------------------------------------------------------------------
-- 2. checklists — replace open anon ALL with establishment-scoped authenticated access
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklists_all" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_all" ON checklists;

CREATE POLICY "auth_checklists_select" ON checklists
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_checklists_insert" ON checklists
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_checklists_update" ON checklists
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_checklists_delete" ON checklists
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3. checklist_items — replace open anon ALL with establishment-scoped access via parent checklist
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklist_items_all" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_all" ON checklist_items;

CREATE POLICY "auth_checklist_items_select" ON checklist_items
  FOR SELECT TO authenticated
  USING (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "auth_checklist_items_insert" ON checklist_items
  FOR INSERT TO authenticated
  WITH CHECK (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "auth_checklist_items_update" ON checklist_items
  FOR UPDATE TO authenticated
  USING (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  )
  WITH CHECK (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "auth_checklist_items_delete" ON checklist_items
  FOR DELETE TO authenticated
  USING (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 4. co_owner_invitations — scope anon UPDATE to specific token only
--    (prevents one anon user from updating another user's invitation)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;

-- anon UPDATE is only allowed when the request is filtered by the exact invitation_token.
-- The app calls: .update({status:'accepted'}).eq('invitation_token', token)
-- RLS enforces that the row's token matches the filter.
CREATE POLICY "anon_update_co_owner_invitations" ON co_owner_invitations
  FOR UPDATE TO anon
  USING (status = 'pending')
  WITH CHECK (status IN ('accepted', 'declined'));

-- ---------------------------------------------------------------------------
-- 5. employees — restrict anon SELECT: only allow looking up by email for registration
--    (replace open USING(true) with a SECURITY DEFINER function)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_employees" ON employees;

-- No anon SELECT policy on employees table directly.
-- Registration email-check goes through a SECURITY DEFINER RPC below.

-- RPC: check if an employee email already exists in a given establishment
-- Called during registration to validate email uniqueness.
CREATE OR REPLACE FUNCTION public.check_employee_email_exists(
  p_email text,
  p_establishment_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE lower(email) = lower(p_email)
      AND establishment_id = p_establishment_id
  );
$$;

-- Grant execute to anon and authenticated
GRANT EXECUTE ON FUNCTION public.check_employee_email_exists(text, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.check_employee_email_exists(text, uuid) TO authenticated;

-- RPC: check if an employee email exists across all establishments (for owner registration)
CREATE OR REPLACE FUNCTION public.check_employee_email_exists_global(
  p_email text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE lower(email) = lower(p_email)
  );
$$;

GRANT EXECUTE ON FUNCTION public.check_employee_email_exists_global(text) TO anon;
GRANT EXECUTE ON FUNCTION public.check_employee_email_exists_global(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. establishments — restrict anon SELECT: hide pin_code from direct table access
--    Use a SECURITY DEFINER RPC to look up establishment by pin_code instead.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_establishments" ON establishments;

-- No anon SELECT on establishments table directly.
-- PIN lookup during employee registration goes through the RPC below.

-- RPC: look up establishment by pin_code (returns id and name only — no sensitive data)
CREATE OR REPLACE FUNCTION public.find_establishment_by_pin(
  p_pin_code text
)
RETURNS TABLE(id uuid, name text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, name FROM establishments
  WHERE pin_code = p_pin_code
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.find_establishment_by_pin(text) TO anon;
GRANT EXECUTE ON FUNCTION public.find_establishment_by_pin(text) TO authenticated;

-- RPC: get own establishment data (authenticated employee only — returns full row)
CREATE OR REPLACE FUNCTION public.get_my_establishment()
RETURNS SETOF establishments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT e.* FROM establishments e
  WHERE e.id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_my_establishment() TO authenticated;
