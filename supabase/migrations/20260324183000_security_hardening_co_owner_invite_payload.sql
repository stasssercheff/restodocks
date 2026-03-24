-- Security hardening: minimize anonymous payload for co-owner invitation lookup.
-- Keeps functionality (accept flow still receives invitation + establishment name/currency),
-- but removes sensitive fields that should never be exposed to anonymous token lookups.

CREATE OR REPLACE FUNCTION public.get_co_owner_invitation_by_token(p_token text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT to_jsonb(r) FROM (
    SELECT inv.*, jsonb_build_object(
      'id', e.id,
      'name', e.name,
      'default_currency', e.default_currency,
      'created_at', e.created_at,
      'updated_at', e.updated_at
    ) as establishments
    FROM co_owner_invitations inv
    JOIN establishments e ON e.id = inv.establishment_id
    WHERE inv.invitation_token = p_token
      AND inv.status IN ('pending', 'accepted')
      AND (inv.expires_at IS NULL OR inv.expires_at > now())
  ) r;
$$;

REVOKE ALL ON FUNCTION public.get_co_owner_invitation_by_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token(text) TO authenticated;
