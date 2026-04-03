-- get_establishment_promo_for_owner: отдать is_disabled для UI (промокод отключён в админке).
-- Смена RETURNS TABLE требует DROP, иначе ERROR: cannot change return type of existing function.

DROP FUNCTION IF EXISTS public.get_establishment_promo_for_owner(uuid);

CREATE FUNCTION public.get_establishment_promo_for_owner(p_establishment_id uuid)
RETURNS TABLE (code text, expires_at timestamptz, is_disabled boolean)
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
    pc.expires_at,
    COALESCE(pc.is_disabled, false)
  FROM public.promo_code_redemptions r
  INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
  WHERE r.establishment_id = p_establishment_id
  ORDER BY r.redeemed_at DESC, r.id DESC
  LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_establishment_promo_for_owner(uuid) IS
  'Код, срок и флаг отключения промокода для заведения; только собственник.';

REVOKE ALL ON FUNCTION public.get_establishment_promo_for_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO service_role;
