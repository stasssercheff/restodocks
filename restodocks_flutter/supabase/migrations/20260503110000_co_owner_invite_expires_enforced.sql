-- Co-owner invitations: enforce TTL (no NULL expires_at), tighten RPC expiry checks,
-- stop echoing invitation_token in anonymous lookup (defense in depth).

-- 1) Backfill and enforce NOT NULL + default for new rows
UPDATE public.co_owner_invitations
SET expires_at = created_at + interval '7 days'
WHERE expires_at IS NULL;

ALTER TABLE public.co_owner_invitations
  ALTER COLUMN expires_at SET DEFAULT (timezone('utc', now()) + interval '7 days');

ALTER TABLE public.co_owner_invitations
  ALTER COLUMN expires_at SET NOT NULL;

COMMENT ON COLUMN public.co_owner_invitations.expires_at IS
  'Invitation valid until this time (UTC). Required — no indefinite invites.';

-- 2) Lookup: pending (before accept) or accepted (after accept, before registration completes).
--    Do not return invitation_token in JSON (client already has the link).
CREATE OR REPLACE FUNCTION public.get_co_owner_invitation_by_token(p_token text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT to_jsonb(r) FROM (
    SELECT
      inv.id,
      inv.establishment_id,
      inv.invited_email,
      inv.invited_by,
      inv.status,
      inv.expires_at,
      inv.created_at,
      inv.updated_at,
      inv.is_view_only_owner,
      jsonb_build_object(
        'id', e.id,
        'name', e.name,
        'pin_code', e.pin_code,
        'default_currency', e.default_currency,
        'created_at', e.created_at,
        'updated_at', e.updated_at
      ) AS establishments
    FROM public.co_owner_invitations inv
    JOIN public.establishments e ON e.id = inv.establishment_id
    WHERE inv.invitation_token = p_token
      AND inv.status IN ('pending', 'accepted')
      AND inv.expires_at > now()
  ) r;
$$;

REVOKE ALL ON FUNCTION public.get_co_owner_invitation_by_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token(text) TO authenticated;

-- 3) Accept: unchanged logic, explicit expiry (column is NOT NULL now)
CREATE OR REPLACE FUNCTION public.accept_co_owner_invitation(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.co_owner_invitations%ROWTYPE;
BEGIN
  SELECT *
  INTO v_row
  FROM public.co_owner_invitations
  WHERE invitation_token = p_token
    AND status = 'pending'
    AND expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'accept_co_owner_invitation: invitation not found or expired';
  END IF;

  UPDATE public.co_owner_invitations
  SET status = 'accepted',
      updated_at = now()
  WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'status', 'accepted'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_co_owner_invitation(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_co_owner_invitation(text) TO anon;
GRANT EXECUTE ON FUNCTION public.accept_co_owner_invitation(text) TO authenticated;

-- 4) Finish registration: require non-expired accepted invite
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
  SELECT inv.*, e.id AS est_id, e.name AS est_name, e.pin_code AS est_pin, e.default_currency AS est_currency
  INTO v_inv
  FROM public.co_owner_invitations inv
  JOIN public.establishments e ON e.id = inv.establishment_id
  WHERE inv.invitation_token = p_invitation_token
    AND inv.status = 'accepted'
    AND inv.expires_at > now()
    AND LOWER(inv.invited_email) = LOWER((SELECT email FROM auth.users WHERE id = auth.uid()));
  IF v_inv IS NULL THEN RAISE EXCEPTION 'create_co_owner_from_invitation: invalid or expired invitation'; END IF;
  IF EXISTS (SELECT 1 FROM public.employees WHERE id = auth.uid()) THEN RAISE EXCEPTION 'create_co_owner_from_invitation: employee already exists'; END IF;
  v_access := CASE WHEN coalesce(v_inv.is_view_only_owner, false) THEN 'view_only' ELSE 'full' END;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');
  INSERT INTO public.employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at)
  SELECT auth.uid(), auth.uid(), trim(p_full_name), nullif(trim(p_surname), ''), au.email, NULL, 'management', NULL, ARRAY['owner'], v_inv.establishment_id, v_personal_pin, 'ru', true, true, v_access, v_now, v_now
  FROM auth.users au WHERE au.id = auth.uid();

  DELETE FROM public.co_owner_invitations
  WHERE invitation_token = p_invitation_token
    AND status = 'accepted';

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
    FROM public.employees WHERE id = auth.uid()
  ) r;
  RETURN v_emp;
END;
$$;
