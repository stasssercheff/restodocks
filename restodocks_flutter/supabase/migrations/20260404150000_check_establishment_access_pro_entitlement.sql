-- Pro допустим только если: (1) оплаченный период IAP в будущем, или (2) есть действующее погашение + валидный promo_codes.
-- Иначе: free — в т.ч. когда промокод удалён (CASCADE снял погашение), отключён или истёк.
-- Удаление недействительных строк погашения снимает блок ESTABLISHMENT_HAS_PROMO и позволяет ввести новый код / оплатить.

CREATE OR REPLACE FUNCTION public.check_establishment_access(p_establishment_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub text;
  v_paid_until timestamptz;
  v_has_active_iap boolean;
  v_has_active_promo boolean;
BEGIN
  -- Сначала убрать привязку к промокоду, который уже не даёт доступ
  DELETE FROM public.promo_code_redemptions r
  USING public.promo_codes pc
  WHERE r.establishment_id = p_establishment_id
    AND r.promo_code_id = pc.id
    AND (
      COALESCE(pc.is_disabled, false)
      OR (pc.starts_at IS NOT NULL AND pc.starts_at > now())
      OR (pc.expires_at IS NOT NULL AND pc.expires_at < now())
    );

  SELECT
    lower(trim(COALESCE(subscription_type, 'free'))),
    pro_paid_until
  INTO v_sub, v_paid_until
  FROM public.establishments
  WHERE id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN 'ok';
  END IF;

  v_has_active_iap :=
    v_paid_until IS NOT NULL
    AND v_paid_until > now();

  SELECT EXISTS (
    SELECT 1
    FROM public.promo_code_redemptions r
    INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
    WHERE r.establishment_id = p_establishment_id
      AND NOT COALESCE(pc.is_disabled, false)
      AND (pc.starts_at IS NULL OR pc.starts_at <= now())
      AND (pc.expires_at IS NULL OR pc.expires_at >= now())
  )
  INTO v_has_active_promo;

  IF v_sub IN ('pro', 'premium')
     AND NOT v_has_active_iap
     AND NOT v_has_active_promo THEN

    UPDATE public.establishments
    SET
      subscription_type = 'free',
      pro_trial_ends_at = NULL,
      pro_paid_until = NULL,
      updated_at = now()
    WHERE id = p_establishment_id;
  END IF;

  RETURN 'ok';
END;
$$;

COMMENT ON FUNCTION public.check_establishment_access(uuid) IS
  'Pro только при активном IAP (pro_paid_until > now()) или действующем промокоде; иначе free. Чистит погашения с отключённым/просроченным кодом.';
