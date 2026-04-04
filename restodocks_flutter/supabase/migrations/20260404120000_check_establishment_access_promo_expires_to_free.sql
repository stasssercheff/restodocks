-- Промокод даёт доступ к Pro-функциям, не к «входу на сайт» (базовое приложение доступно на free).
-- Истёкший/отключённый промокод: перевести заведение на free (Pro снимается), без logout.
-- Ранее возвращался 'expired' → клиент делал logout() — неверно для продуктовой модели.

CREATE OR REPLACE FUNCTION public.check_establishment_access(p_establishment_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.promo_codes%rowtype;
  v_has_future_paid boolean;
BEGIN
  SELECT pc.* INTO v_row
  FROM public.promo_code_redemptions r
  INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
  WHERE r.establishment_id = p_establishment_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 'ok';
  END IF;

  IF COALESCE(v_row.is_disabled, false)
     OR (v_row.expires_at IS NOT NULL AND v_row.expires_at < now()) THEN

    -- Активная оплаченная подписка с датой окончания в будущем — не меняем тариф.
    SELECT EXISTS (
      SELECT 1
      FROM public.establishments e
      WHERE e.id = p_establishment_id
        AND e.pro_paid_until IS NOT NULL
        AND e.pro_paid_until > now()
    ) INTO v_has_future_paid;

    IF v_has_future_paid THEN
      RETURN 'ok';
    END IF;

    UPDATE public.establishments
    SET
      subscription_type = 'free',
      pro_trial_ends_at = NULL,
      updated_at = now()
    WHERE id = p_establishment_id
      AND COALESCE(lower(trim(subscription_type)), 'free') IN ('pro', 'premium');

    RETURN 'ok';
  END IF;

  RETURN 'ok';
END;
$$;

COMMENT ON FUNCTION public.check_establishment_access(uuid) IS
  'Синхронизация тарифа по промокоду: истечение/отключение — только снятие Pro-функций (free), вход в приложение не блокируется.';

COMMENT ON COLUMN public.promo_codes.is_disabled IS
  'Если true — код нельзя применить; у заведений с этим промо снимается Pro (переход на free в check_establishment_access).';
