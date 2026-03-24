-- P0 finalize: close remaining high-risk policy/function gaps after prior hardening.

-- 1) Ensure establishment_documents stays tenant-scoped (overrides any older open policy migration).
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
);

CREATE POLICY "auth_establishment_documents_update"
ON establishment_documents
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

CREATE POLICY "auth_establishment_documents_delete"
ON establishment_documents
FOR DELETE
TO authenticated
USING (
  establishment_id IN (SELECT current_user_establishment_ids())
  AND NOT is_current_user_view_only_owner()
);

-- 2) co_owner invitation: add expiry check for anon update and one-time consume in RPC.
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;
CREATE POLICY "anon_update_co_owner_invitations"
ON co_owner_invitations
FOR UPDATE
TO anon
USING (
  status = 'pending'
  AND invitation_token IS NOT NULL
  AND invitation_token <> ''
  AND (expires_at IS NULL OR expires_at > now())
)
WITH CHECK (
  status IN ('accepted', 'declined')
);

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
  WHERE inv.invitation_token = p_invitation_token
    AND inv.status = 'accepted'
    AND (inv.expires_at IS NULL OR inv.expires_at > now())
    AND LOWER(inv.invited_email) = LOWER((SELECT email FROM auth.users WHERE id = auth.uid()));
  IF v_inv IS NULL THEN RAISE EXCEPTION 'create_co_owner_from_invitation: invalid or expired invitation'; END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE id = auth.uid()) THEN RAISE EXCEPTION 'create_co_owner_from_invitation: employee already exists'; END IF;
  v_access := CASE WHEN coalesce(v_inv.is_view_only_owner, false) THEN 'view_only' ELSE 'full' END;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  INSERT INTO employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at)
  SELECT auth.uid(), auth.uid(), trim(p_full_name), nullif(trim(p_surname), ''), au.email, NULL, 'management', NULL, ARRAY['owner'], v_inv.establishment_id, v_personal_pin, 'ru', true, true, v_access, v_now, v_now
  FROM auth.users au WHERE au.id = auth.uid();

  DELETE FROM co_owner_invitations
  WHERE invitation_token = p_invitation_token
    AND status = 'accepted';

  SELECT to_jsonb(r) INTO v_emp FROM (SELECT id, full_name, surname, email, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at FROM employees WHERE id = auth.uid()) r;
  RETURN v_emp;
END;
$$;

-- 3) product_aliases/product_alias_rejections: disable anon writes.
ALTER TABLE product_aliases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_insert_product_aliases" ON product_aliases;
DROP POLICY IF EXISTS "anon_update_product_aliases" ON product_aliases;

CREATE POLICY "auth_insert_product_aliases"
ON product_aliases
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NULL
  OR establishment_id IN (SELECT current_user_establishment_ids())
);

CREATE POLICY "auth_update_product_aliases"
ON product_aliases
FOR UPDATE
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT current_user_establishment_ids())
)
WITH CHECK (
  establishment_id IS NULL
  OR establishment_id IN (SELECT current_user_establishment_ids())
);

ALTER TABLE product_alias_rejections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_insert_product_alias_rejections" ON product_alias_rejections;
DROP POLICY IF EXISTS "anon_select_product_alias_rejections" ON product_alias_rejections;

CREATE POLICY "auth_select_product_alias_rejections"
ON product_alias_rejections
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT current_user_establishment_ids())
);

CREATE POLICY "auth_insert_product_alias_rejections"
ON product_alias_rejections
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NULL
  OR establishment_id IN (SELECT current_user_establishment_ids())
);

-- 4) ai_ttk_daily_usage: disable anon writes (keep read for compatibility).
ALTER TABLE ai_ttk_daily_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "anon_insert_ai_ttk_usage" ON ai_ttk_daily_usage;
DROP POLICY IF EXISTS "anon_update_ai_ttk_usage" ON ai_ttk_daily_usage;

CREATE POLICY "auth_insert_ai_ttk_usage"
ON ai_ttk_daily_usage
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IN (SELECT current_user_establishment_ids())
);

CREATE POLICY "auth_update_ai_ttk_usage"
ON ai_ttk_daily_usage
FOR UPDATE
TO authenticated
USING (
  establishment_id IN (SELECT current_user_establishment_ids())
)
WITH CHECK (
  establishment_id IN (SELECT current_user_establishment_ids())
);
