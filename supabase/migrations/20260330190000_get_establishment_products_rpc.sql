-- RPC для фолбэка номенклатуры (ProductStore). Ранее существовала только в отдельном .sql без миграции → 404 на проде.
-- Доступ: владелец заведения ИЛИ активный сотрудник с привязкой auth_user_id (не только owner_id).

CREATE OR REPLACE FUNCTION public.get_establishment_products(est_id UUID)
RETURNS TABLE (
  product_id UUID,
  price NUMERIC,
  currency TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.id = est_id
      AND (
        e.owner_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.employees emp
          WHERE emp.establishment_id = e.id
            AND emp.auth_user_id = auth.uid()
            AND COALESCE(emp.is_active, true)
        )
      )
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT ep.product_id, ep.price, ep.currency
  FROM public.establishment_products ep
  WHERE ep.establishment_id = est_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_establishment_products(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_establishment_products(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_establishment_products(UUID) TO service_role;
