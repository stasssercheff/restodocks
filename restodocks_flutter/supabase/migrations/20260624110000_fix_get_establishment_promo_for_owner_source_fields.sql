-- Ensure owner promo RPC always returns current promo template fields
-- (tier/add-on packs/note), including activation-duration expiry calculation.

DROP FUNCTION IF EXISTS public.get_establishment_promo_for_owner(uuid);

CREATE FUNCTION public.get_establishment_promo_for_owner(p_establishment_id uuid)
RETURNS TABLE (
  code text,
  expires_at timestamptz,
  is_disabled boolean,
  grants_subscription_type text,
  grants_employee_slot_packs integer,
  grants_branch_slot_packs integer,
  grants_additive_only boolean,
  max_employees integer,
  promo_template_note text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'get_establishment_promo_for_owner: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'get_establishment_promo_for_owner: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.employees e
    WHERE e.establishment_id = p_establishment_id
      AND e.auth_user_id = auth.uid()
      AND COALESCE(e.is_active, true)
      AND 'owner' = ANY (e.roles)
  ) THEN
    RAISE EXCEPTION 'get_establishment_promo_for_owner: owner only';
  END IF;

  RETURN QUERY
  SELECT
    pc.code::text,
    CASE
      WHEN pc.activation_duration_days IS NOT NULL AND pc.activation_duration_days > 0 THEN
        r.redeemed_at + make_interval(days => pc.activation_duration_days)
      ELSE
        pc.expires_at
    END AS expires_at,
    COALESCE(pc.is_disabled, false),
    lower(trim(COALESCE(pc.grants_subscription_type, 'pro')))::text,
    COALESCE(pc.grants_employee_slot_packs, 0)::integer,
    COALESCE(pc.grants_branch_slot_packs, 0)::integer,
    COALESCE(pc.grants_additive_only, false)::boolean,
    pc.max_employees,
    NULLIF(TRIM(pc.note), '')::text
  FROM public.promo_code_redemptions r
  INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
  WHERE r.establishment_id = p_establishment_id
  ORDER BY r.redeemed_at DESC, r.id DESC
  LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_establishment_promo_for_owner(uuid) IS
  'Owner promo info: code, effective expiry, disabled flag, current promo template fields (tier/add-on packs/max_employees/note).';

REVOKE ALL ON FUNCTION public.get_establishment_promo_for_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO service_role;
