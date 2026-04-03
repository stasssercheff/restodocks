-- Co-owner invite link must be one-time.
-- After accept, rotate token/hash and return fresh registration token.
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
  v_next_token text := encode(gen_random_bytes(24), 'hex');
  v_next_hash text := encode(extensions.digest(convert_to(v_next_token, 'UTF8'), 'sha256'::text), 'hex');
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
      invitation_token = NULL,
      invitation_token_hash = v_next_hash,
      updated_at = now()
  WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'status', 'accepted',
    'registration_token', v_next_token
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_co_owner_invitation(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_co_owner_invitation(text) TO anon;
GRANT EXECUTE ON FUNCTION public.accept_co_owner_invitation(text) TO authenticated;
