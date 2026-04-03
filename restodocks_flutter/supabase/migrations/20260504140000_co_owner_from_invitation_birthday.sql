-- Co-owner registration: optional birthday on employee row.
CREATE OR REPLACE FUNCTION public.create_co_owner_from_invitation(
  p_invitation_token text,
  p_full_name text,
  p_surname text DEFAULT NULL,
  p_birthday date DEFAULT NULL
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
  INSERT INTO public.employees (id, auth_user_id, full_name, surname, email, password_hash, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, birthday, created_at, updated_at)
  SELECT auth.uid(), auth.uid(), trim(p_full_name), nullif(trim(p_surname), ''), au.email, NULL, 'management', NULL, ARRAY['owner'], v_inv.establishment_id, v_personal_pin, 'ru', true, true, v_access, p_birthday, v_now, v_now
  FROM auth.users au WHERE au.id = auth.uid();

  DELETE FROM public.co_owner_invitations
  WHERE (invitation_token_hash = v_h
    OR (invitation_token IS NOT NULL AND invitation_token = v_raw))
    AND status = 'accepted';

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles, establishment_id, personal_pin, preferred_language, is_active, data_access_enabled, owner_access_level, birthday, created_at, updated_at
    FROM public.employees WHERE id = auth.uid()
  ) r;
  RETURN v_emp;
END;
$$;
