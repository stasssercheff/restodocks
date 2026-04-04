-- Срок окончания промокода обязателен (как в админке по продукту). NULL раньше означал «без срока» в check_establishment_access.
-- 1) Заполняем legacy-строки. 2) NOT NULL. 3) Ужесточаем check_establishment_access.

UPDATE public.promo_codes
SET expires_at = COALESCE(
  expires_at,
  COALESCE(starts_at, created_at) + interval '365 days'
)
WHERE expires_at IS NULL;

ALTER TABLE public.promo_codes
  ALTER COLUMN expires_at SET NOT NULL;

COMMENT ON COLUMN public.promo_codes.expires_at IS
  'Дата/время окончания действия промокода (обязательно; задаётся в админке).';

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
  DELETE FROM public.promo_code_redemptions r
  USING public.promo_codes pc
  WHERE r.establishment_id = p_establishment_id
    AND r.promo_code_id = pc.id
    AND (
      COALESCE(pc.is_disabled, false)
      OR (pc.starts_at IS NOT NULL AND pc.starts_at > now())
      OR pc.expires_at < now()
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
      AND pc.expires_at >= now()
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
  'Pro только при активном IAP (pro_paid_until > now()) или действующем промокоде с непустым expires_at >= now(); иначе free.';
