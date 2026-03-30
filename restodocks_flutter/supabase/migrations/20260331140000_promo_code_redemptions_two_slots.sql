-- Два заведения на один промокод + применение кода в настройках (уже зарегистрированное заведение).

CREATE TABLE IF NOT EXISTS public.promo_code_redemptions (
  id bigserial PRIMARY KEY,
  promo_code_id bigint NOT NULL REFERENCES public.promo_codes (id) ON DELETE CASCADE,
  establishment_id uuid NOT NULL REFERENCES public.establishments (id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (promo_code_id, establishment_id),
  UNIQUE (establishment_id)
);

COMMENT ON TABLE public.promo_code_redemptions IS
  'Погашение промокода заведением; не более 2 разных заведений на один promo_codes.id.';

ALTER TABLE public.promo_code_redemptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role full access promo_code_redemptions" ON public.promo_code_redemptions;
CREATE POLICY "service_role full access promo_code_redemptions"
  ON public.promo_code_redemptions
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Перенос существующих привязок
INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id, redeemed_at)
SELECT pc.id, pc.used_by_establishment_id, COALESCE(pc.used_at, now())
FROM public.promo_codes pc
WHERE pc.used_by_establishment_id IS NOT NULL
ON CONFLICT (establishment_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.promo_code_redemptions_limit_before()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF (
    SELECT COUNT(*)::int
    FROM public.promo_code_redemptions
    WHERE promo_code_id = NEW.promo_code_id
  ) >= 2 THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_promo_code_redemptions_limit ON public.promo_code_redemptions;
CREATE TRIGGER trg_promo_code_redemptions_limit
  BEFORE INSERT ON public.promo_code_redemptions
  FOR EACH ROW
  EXECUTE FUNCTION public.promo_code_redemptions_limit_before();

CREATE OR REPLACE FUNCTION public.promo_code_redemptions_sync_promo_row()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_pc bigint;
BEGIN
  v_pc := COALESCE(NEW.promo_code_id, OLD.promo_code_id);
  UPDATE public.promo_codes pc
  SET
    is_used = (
      SELECT COUNT(*) >= 2
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    ),
    used_at = (
      SELECT MIN(r.redeemed_at)
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
    ),
    used_by_establishment_id = (
      SELECT r.establishment_id
      FROM public.promo_code_redemptions r
      WHERE r.promo_code_id = pc.id
      ORDER BY r.redeemed_at ASC
      LIMIT 1
    )
  WHERE pc.id = v_pc;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_promo_code_redemptions_sync ON public.promo_code_redemptions;
CREATE TRIGGER trg_promo_code_redemptions_sync
  AFTER INSERT OR DELETE OR UPDATE OF promo_code_id, establishment_id
  ON public.promo_code_redemptions
  FOR EACH ROW
  EXECUTE FUNCTION public.promo_code_redemptions_sync_promo_row();

-- Синхронизировать строки promo_codes после бэкапа
UPDATE public.promo_codes pc
SET
  is_used = (
    SELECT COUNT(*) >= 2
    FROM public.promo_code_redemptions r
    WHERE r.promo_code_id = pc.id
  ),
  used_at = (
    SELECT MIN(r.redeemed_at)
    FROM public.promo_code_redemptions r
    WHERE r.promo_code_id = pc.id
  ),
  used_by_establishment_id = (
    SELECT r.establishment_id
    FROM public.promo_code_redemptions r
    WHERE r.promo_code_id = pc.id
    ORDER BY r.redeemed_at ASC
    LIMIT 1
  );

CREATE OR REPLACE FUNCTION public.check_establishment_access(p_establishment_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.promo_codes%rowtype;
BEGIN
  SELECT pc.* INTO v_row
  FROM public.promo_code_redemptions r
  INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
  WHERE r.establishment_id = p_establishment_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 'ok';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RETURN 'expired';
  END IF;

  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION public.check_employee_limit(p_establishment_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max integer;
  v_count integer;
BEGIN
  SELECT pc.max_employees INTO v_max
  FROM public.promo_code_redemptions r
  INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
  WHERE r.establishment_id = p_establishment_id
  LIMIT 1;

  IF NOT FOUND OR v_max IS NULL THEN
    RETURN 'ok';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.employees
  WHERE establishment_id = p_establishment_id
    AND is_active = true;

  IF v_count >= v_max THEN
    RETURN 'limit_reached';
  END IF;

  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION public.get_establishment_promo_for_owner(p_establishment_id uuid)
RETURNS TABLE (code text, expires_at timestamptz)
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
  SELECT pc.code::text, pc.expires_at
  FROM public.promo_code_redemptions r
  INNER JOIN public.promo_codes pc ON pc.id = r.promo_code_id
  WHERE r.establishment_id = p_establishment_id
  ORDER BY r.redeemed_at DESC, r.id DESC
  LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_establishment_promo_for_owner(uuid) IS
  'Код и срок промокода для заведения (через погашения); только собственник.';

REVOKE ALL ON FUNCTION public.get_establishment_promo_for_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_establishment_promo_for_owner(uuid) TO service_role;

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
  v_row public.promo_codes%rowtype;
  v_est_id uuid;
  v_est jsonb;
  v_n int;
BEGIN
  SELECT * INTO v_row
  FROM public.promo_codes
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

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id)
  VALUES (v_row.id, v_est_id);

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
  'Регистрация с промокодом; один код — до 2 заведений; Pro с первого дня.';

CREATE OR REPLACE FUNCTION public.apply_promo_to_establishment_for_owner(
  p_establishment_id uuid,
  p_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.promo_codes%rowtype;
  v_n int;
  v_sub text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.employees e
    WHERE e.establishment_id = p_establishment_id
      AND e.auth_user_id = auth.uid()
      AND COALESCE(e.is_active, true)
      AND 'owner' = ANY (e.roles)
  ) THEN
    RAISE EXCEPTION 'apply_promo_to_establishment_for_owner: owner only';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.promo_code_redemptions WHERE establishment_id = p_establishment_id
  ) THEN
    RAISE EXCEPTION 'ESTABLISHMENT_HAS_PROMO';
  END IF;

  SELECT * INTO v_row
  FROM public.promo_codes
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

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  INSERT INTO public.promo_code_redemptions (promo_code_id, establishment_id)
  VALUES (v_row.id, p_establishment_id);

  SELECT lower(trim(COALESCE(subscription_type, 'free'))) INTO v_sub
  FROM public.establishments
  WHERE id = p_establishment_id;

  UPDATE public.establishments
  SET
    subscription_type = CASE WHEN v_sub = 'premium' THEN subscription_type ELSE 'pro' END,
    pro_trial_ends_at = CASE WHEN v_sub = 'premium' THEN pro_trial_ends_at ELSE NULL END,
    updated_at = now()
  WHERE id = p_establishment_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.apply_promo_to_establishment_for_owner(uuid, text) IS
  'Владелец применяет админский промокод к уже существующему заведению; до 2 заведений на код.';

REVOKE ALL ON FUNCTION public.apply_promo_to_establishment_for_owner(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_promo_to_establishment_for_owner(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_promo_to_establishment_for_owner(uuid, text) TO service_role;
