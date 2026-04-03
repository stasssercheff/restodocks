-- Co-owner invitations: store SHA-256 hash of token (plaintext only returned once from RPC).
-- Legacy rows keep invitation_token until consumed; matching uses hash OR legacy plain token.
-- Hash: encode(extensions.digest(convert_to(..., 'UTF8'), 'sha256'), 'hex') — pgcrypto в схеме extensions.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.co_owner_invitations
  ADD COLUMN IF NOT EXISTS invitation_token_hash text;

UPDATE public.co_owner_invitations
SET invitation_token_hash = encode(
    extensions.digest(convert_to(invitation_token, 'UTF8'), 'sha256'::text),
    'hex'
  )
WHERE invitation_token_hash IS NULL
  AND invitation_token IS NOT NULL;

ALTER TABLE public.co_owner_invitations
  ALTER COLUMN invitation_token DROP NOT NULL;

ALTER TABLE public.co_owner_invitations
  ALTER COLUMN invitation_token_hash SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_co_owner_invitations_token_hash
  ON public.co_owner_invitations (invitation_token_hash);

COMMENT ON COLUMN public.co_owner_invitations.invitation_token_hash IS
  'SHA-256 hex digest of invitation token; legacy rows may also have invitation_token until migrated.';

COMMENT ON COLUMN public.co_owner_invitations.invitation_token IS
  'Legacy plaintext token; new invites use NULL here (hash-only).';

-- Owner creates invite; returns plaintext token once in JSON for the link/email.
CREATE OR REPLACE FUNCTION public.create_co_owner_invitation(
  p_establishment_id uuid,
  p_invited_email text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_invited_by uuid;
  v_token text;
  v_hash text;
  v_view_only boolean;
  v_id uuid;
  v_expires timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'create_co_owner_invitation: must be authenticated';
  END IF;

  SELECT emp.id INTO v_invited_by
  FROM public.employees emp
  WHERE emp.establishment_id = p_establishment_id
    AND emp.auth_user_id = auth.uid()
    AND 'owner' = ANY(emp.roles)
  LIMIT 1;

  IF v_invited_by IS NULL THEN
    RAISE EXCEPTION 'create_co_owner_invitation: not an owner of this establishment';
  END IF;

  v_view_only := (SELECT count(*) > 1 FROM public.establishments WHERE owner_id = auth.uid());

  v_token := replace(
    replace(rtrim(encode(extensions.gen_random_bytes(32), 'base64'), '='),
      '+', '-'),
    '/', '_'
  );
  v_hash := encode(extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'::text), 'hex');
  v_expires := timezone('utc', now()) + interval '7 days';

  INSERT INTO public.co_owner_invitations (
    establishment_id,
    invited_email,
    invited_by,
    invitation_token,
    invitation_token_hash,
    status,
    expires_at,
    is_view_only_owner
  ) VALUES (
    p_establishment_id,
    trim(p_invited_email),
    v_invited_by,
    NULL,
    v_hash,
    'pending',
    v_expires,
    v_view_only
  )
  RETURNING id, expires_at INTO v_id, v_expires;

  RETURN jsonb_build_object(
    'id', v_id,
    'invitation_token', v_token,
    'expires_at', v_expires
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_co_owner_invitation(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_co_owner_invitation(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_co_owner_invitation_by_token(p_token text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
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
    CROSS JOIN LATERAL (
      SELECT
        trim(p_token) AS raw_t,
        encode(
          extensions.digest(convert_to(trim(p_token), 'UTF8'), 'sha256'::text),
          'hex'
        ) AS tok_h
    ) t
    WHERE (inv.invitation_token_hash = t.tok_h
      OR (inv.invitation_token IS NOT NULL AND inv.invitation_token = t.raw_t))
      AND inv.status IN ('pending', 'accepted')
      AND inv.expires_at > now()
  ) r;
$$;

REVOKE ALL ON FUNCTION public.get_co_owner_invitation_by_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_co_owner_invitation(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row public.co_owner_invitations%ROWTYPE;
  v_raw text := trim(p_token);
  v_h text := encode(extensions.digest(convert_to(trim(p_token), 'UTF8'), 'sha256'::text), 'hex');
BEGIN
  SELECT inv.*
  INTO v_row
  FROM public.co_owner_invitations inv
  WHERE (inv.invitation_token_hash = v_h
    OR (inv.invitation_token IS NOT NULL AND inv.invitation_token = v_raw))
    AND inv.status = 'pending'
    AND inv.expires_at > now()
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

CREATE OR REPLACE FUNCTION public.create_co_owner_from_invitation(
  p_invitation_token text,
  p_full_name text,
  p_surname text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_inv record;
  v_access text;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
  v_raw text := trim(p_invitation_token);
  v_h text := encode(
    extensions.digest(convert_to(trim(p_invitation_token), 'UTF8'), 'sha256'::text),
    'hex'
  );
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'create_co_owner_from_invitation: must be authenticated'; END IF;
  SELECT inv.*, e.id AS est_id, e.name AS est_name, e.pin_code AS est_pin, e.default_currency AS est_currency
  INTO v_inv
  FROM public.co_owner_invitations inv
  JOIN public.establishments e ON e.id = inv.establishment_id
  WHERE (inv.invitation_token_hash = v_h
    OR (inv.invitation_token IS NOT NULL AND inv.invitation_token = v_raw))
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
  WHERE (invitation_token_hash = v_h
    OR (invitation_token IS NOT NULL AND invitation_token = v_raw))
    AND status = 'accepted';

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
    FROM public.employees WHERE id = auth.uid()
  ) r;
  RETURN v_emp;
END;
$$;
