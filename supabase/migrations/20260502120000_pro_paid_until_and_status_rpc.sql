-- Единый механизм Pro-статуса для сайта/приложений независимо от источника оплаты.
-- Источники (Apple/promo/будущие провайдеры) пишут в establishments.subscription_type + pro_paid_until.

ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS pro_paid_until TIMESTAMPTZ;

COMMENT ON COLUMN public.establishments.pro_paid_until IS
  'Дата окончания оплаченного Pro. NULL = бессрочный Pro (например, промокод/ручная выдача).';

CREATE OR REPLACE FUNCTION public.is_establishment_paid_pro_active(p_establishment_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription_type text;
  v_paid_until timestamptz;
BEGIN
  SELECT lower(trim(COALESCE(e.subscription_type, 'free'))), e.pro_paid_until
    INTO v_subscription_type, v_paid_until
  FROM public.establishments e
  WHERE e.id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_subscription_type NOT IN ('pro', 'premium') THEN
    RETURN false;
  END IF;

  -- NULL = бессрочный доступ (промокод/ручной grant).
  IF v_paid_until IS NULL THEN
    RETURN true;
  END IF;

  RETURN v_paid_until > now();
END;
$$;

COMMENT ON FUNCTION public.is_establishment_paid_pro_active(uuid) IS
  'Проверка оплаченного Pro: subscription_type in (pro,premium) и pro_paid_until > now() (или NULL для бессрочного grant).';

CREATE OR REPLACE FUNCTION public.is_establishment_pro_effective(p_establishment_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trial_until timestamptz;
BEGIN
  SELECT e.pro_trial_ends_at
    INTO v_trial_until
  FROM public.establishments e
  WHERE e.id = p_establishment_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  RETURN public.is_establishment_paid_pro_active(p_establishment_id)
    OR (v_trial_until IS NOT NULL AND v_trial_until > now());
END;
$$;

COMMENT ON FUNCTION public.is_establishment_pro_effective(uuid) IS
  'Проверка эффективного Pro: оплаченный Pro (в т.ч. бессрочный grant) ИЛИ активный trial 72 часа.';

CREATE OR REPLACE FUNCTION public.get_establishment_pro_status(p_establishment_id uuid)
RETURNS TABLE(
  is_pro_effective boolean,
  is_paid_pro boolean,
  subscription_type text,
  pro_paid_until timestamptz,
  pro_trial_ends_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'get_establishment_pro_status: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'get_establishment_pro_status: access denied';
  END IF;

  RETURN QUERY
  SELECT
    public.is_establishment_pro_effective(e.id) AS is_pro_effective,
    public.is_establishment_paid_pro_active(e.id) AS is_paid_pro,
    COALESCE(lower(trim(e.subscription_type)), 'free') AS subscription_type,
    e.pro_paid_until,
    e.pro_trial_ends_at
  FROM public.establishments e
  WHERE e.id = p_establishment_id
  LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_establishment_pro_status(uuid) IS
  'Единая RPC-точка для клиентов: возвращает effective/paid Pro статус и сроки.';

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

  IF NOT public.is_establishment_pro_effective(p_establishment_id) THEN
    RAISE EXCEPTION 'EXPENSES_PRO_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'effective Pro required (paid subscription, promo grant or active trial)';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.require_establishment_pro_for_expenses(uuid) IS
  'Pro для расходов: единая проверка effective Pro через is_establishment_pro_effective().';
