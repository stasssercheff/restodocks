-- RPC/permission regression checks focused on IDOR and privilege abuse.
-- Run in staging first.

BEGIN;

-- 1) Inspect EXECUTE grants for sensitive RPCs.
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'create_owner_employee',
    'create_employee_self_register',
    'save_pending_owner_registration',
    'get_co_owner_invitation_by_token'
  )
ORDER BY routine_name, grantee;

-- 2) Assert invitation payload does not expose sensitive establishment fields.
DO $$
DECLARE
  token_value text;
  payload jsonb;
BEGIN
  SELECT invitation_token
    INTO token_value
  FROM co_owner_invitations
  WHERE invitation_token IS NOT NULL
    AND status IN ('pending', 'accepted')
  LIMIT 1;

  IF token_value IS NULL THEN
    RAISE NOTICE 'No invitation token found for payload test; skipped';
    RETURN;
  END IF;

  SELECT public.get_co_owner_invitation_by_token(token_value)
    INTO payload;

  IF payload IS NULL THEN
    RAISE NOTICE 'Invitation payload null; skipped';
    RETURN;
  END IF;

  IF (payload -> 'establishments') ? 'pin_code' THEN
    RAISE EXCEPTION 'Security regression: pin_code exposed in invitation payload';
  END IF;

  IF (payload -> 'establishments') ? 'owner_id' THEN
    RAISE EXCEPTION 'Security regression: owner_id exposed in invitation payload';
  END IF;

  RAISE NOTICE 'PASS: invitation payload does not expose pin_code/owner_id';
END $$;

ROLLBACK;
