-- Проблема: register_company_with_promo (20260430180000) только UPDATE promo_codes и не создаёт
-- строку в promo_code_redemptions → триггер promo_code_redemptions_sync_promo_row не отражает погашение
-- в канонической таблице; плюс исторически is_used сбрасывался формулой COUNT(*) >= 2.
-- Решение: при регистрации с промо — INSERT в promo_code_redemptions (как в 20260331140000);
-- is_used/used_at/used_by подтягивает триггер. Бэкапл строк для уже погашенных кодов без redemptions.

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
  v_n int;
BEGIN
  SELECT * INTO v_row FROM public.promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  SELECT COUNT(*)::int INTO v_n
  FROM public.promo_code_redemptions
  WHERE promo_code_id = v_row.id;

  IF v_n >= 2 THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  -- Ручная отметка «использован» в админке без строки в redemptions
  IF v_row.is_used AND v_n = 0 THEN
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

  INSERT INTO public.pos_dining_tables (
    establishment_id,
    floor_name,
    room_name,
    table_number,
    sort_order,
    status
  )
  VALUES (
    v_est_id,
    '1',
    'Основной',
    1,
    0,
    'free'
  );

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id, redeemed_at)
  VALUES (v_row.id, v_est_id, now());

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
  'Регистрация с промокодом; строка погашения в promo_code_redemptions; до 2 заведений на код.';

-- Заведения, у которых в promo_codes есть used_by, но нет соответствующей строки погашения
INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id, redeemed_at)
SELECT pc.id, pc.used_by_establishment_id, COALESCE(pc.used_at, now())
FROM public.promo_codes pc
WHERE pc.used_by_establishment_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.promo_code_redemptions r
    WHERE r.promo_code_id = pc.id
      AND r.establishment_id = pc.used_by_establishment_id
  )
ON CONFLICT DO NOTHING;

-- Пересчитать колонки отображения в админке (как в 20260401150000)
UPDATE public.promo_codes pc
SET
  is_used = (
    EXISTS (
      SELECT 1
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    )
    OR (pc.used_by_establishment_id IS NOT NULL)
  ),
  used_at = COALESCE(
    (
      SELECT MIN(r.redeemed_at)
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    ),
    pc.used_at
  ),
  used_by_establishment_id = COALESCE(
    (
      SELECT r.establishment_id
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
      ORDER BY r.redeemed_at ASC
      LIMIT 1
    ),
    pc.used_by_establishment_id
  );
