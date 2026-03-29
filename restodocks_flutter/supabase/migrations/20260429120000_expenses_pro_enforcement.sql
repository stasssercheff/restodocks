-- Раздел «Расходы» (Pro): серверная проверка подписки.
-- Клиент не может обойти через прямой SELECT — агрегирующие списки только через RPC ниже.

ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS subscription_type TEXT;

COMMENT ON COLUMN public.establishments.subscription_type IS 'free | pro | premium — доступ к Pro-функциям';

-- Проверка: пользователь состоит в заведении и у заведения подписка pro/premium.
CREATE OR REPLACE FUNCTION public.require_establishment_pro_for_expenses(p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'require_establishment_pro_for_expenses: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'require_establishment_pro_for_expenses: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.id = p_establishment_id
      AND COALESCE(lower(trim(e.subscription_type)), 'free') IN ('pro', 'premium')
  ) THEN
    RAISE EXCEPTION 'EXPENSES_PRO_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'subscription_type must be pro or premium';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.require_establishment_pro_for_expenses(uuid) IS
  'Вызывать перед загрузкой данных экрана «Расходы» / ФЗП; иначе исключение EXPENSES_PRO_REQUIRED.';

-- Список документов заказов продуктов для экрана «Расходы» (только Pro).
CREATE OR REPLACE FUNCTION public.list_order_documents_for_expenses(p_establishment_id uuid)
RETURNS SETOF public.order_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_establishment_pro_for_expenses(p_establishment_id);
  RETURN QUERY
  SELECT o.*
  FROM public.order_documents o
  WHERE o.establishment_id = p_establishment_id
  ORDER BY o.created_at DESC;
END;
$$;

-- Список документов инвентаризации/списаний для вкладки «Расходы» (только Pro).
CREATE OR REPLACE FUNCTION public.list_inventory_documents_for_expenses(p_establishment_id uuid)
RETURNS SETOF public.inventory_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_establishment_pro_for_expenses(p_establishment_id);
  RETURN QUERY
  SELECT d.*
  FROM public.inventory_documents d
  WHERE d.establishment_id = p_establishment_id
  ORDER BY d.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.require_establishment_pro_for_expenses(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.require_establishment_pro_for_expenses(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_order_documents_for_expenses(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_order_documents_for_expenses(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_inventory_documents_for_expenses(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_inventory_documents_for_expenses(uuid) TO authenticated;
