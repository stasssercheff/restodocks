-- Регистрация компании без промокода: 72 ч доступа к Pro-функциям (pro_trial_ends_at), затем free.
-- Промокод из админки по-прежнему даёт постоянный Pro через register_company_with_promo.
--
-- ВАЖНО: выполняйте весь файл одним запуском (Supabase CLI, psql, «Run» без выделения куска).
-- Если в SQL Editor запускать по одной команде, разбитой по «;», тело PL/pgSQL внутри $$…$$
-- обрежется → ERROR 42601 syntax error at end of input (часто LINE 0).

-- subscription_type — из 20260429120000_expenses_pro_enforcement; на части БД миграция не накатывалась.
ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS subscription_type TEXT,
  ADD COLUMN IF NOT EXISTS pro_trial_ends_at TIMESTAMPTZ;

COMMENT ON COLUMN public.establishments.subscription_type IS 'free | pro | premium — доступ к Pro-функциям';

COMMENT ON COLUMN public.establishments.pro_trial_ends_at IS
  'До этой даты действует пробный Pro после регистрации без промокода (72 ч с момента создания).';

-- Серверные проверки Pro: подписка pro/premium ИЛИ активный пробный период.
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
      AND (
        COALESCE(lower(trim(e.subscription_type)), 'free') IN ('pro', 'premium')
        OR (e.pro_trial_ends_at IS NOT NULL AND e.pro_trial_ends_at > now())
      )
  ) THEN
    RAISE EXCEPTION 'EXPENSES_PRO_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'subscription_type must be pro/premium or pro_trial active';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.require_establishment_pro_for_expenses(uuid) IS
  'Pro для расходов: subscription pro/premium или активный pro_trial_ends_at.';

-- Регистрация без промокода (единственный безопасный путь наряду с register_company_with_promo).
CREATE OR REPLACE FUNCTION public.register_company_without_promo(
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_est_id uuid;
  v_est jsonb;
  v_trial_end timestamptz := now() + interval '72 hours';
BEGIN
  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    pro_trial_ends_at,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'free',
    v_trial_end,
    now(),
    now()
  );

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      pro_trial_ends_at,
      created_at,
      updated_at
    FROM public.establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_without_promo(text, text, text) IS
  'Регистрация компании без промокода; 72 ч Pro через pro_trial_ends_at, subscription_type = free.';

REVOKE ALL ON FUNCTION public.register_company_without_promo(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_company_without_promo(text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.register_company_without_promo(text, text, text) TO authenticated;

-- Возврат промокодной регистрации тоже отдаёт pro_trial_ends_at (обычно NULL).
CREATE OR REPLACE FUNCTION public.register_company_with_promo(
  p_code text,
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row promo_codes%rowtype;
  v_est_id uuid;
  v_est jsonb;
BEGIN
  SELECT * INTO v_row FROM public.promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF v_row.is_used THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    pro_trial_ends_at,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'pro',
    NULL,
    now(),
    now()
  );

  UPDATE public.promo_codes
  SET is_used = true, used_by_establishment_id = v_est_id, used_at = now()
  WHERE id = v_row.id;

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      pro_trial_ends_at,
      created_at,
      updated_at
    FROM public.establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_with_promo(text, text, text, text) IS
  'Регистрация с промокодом из админки; подписка Pro, без пробного окна.';
