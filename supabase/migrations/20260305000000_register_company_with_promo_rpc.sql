-- =============================================================================
-- ЗАЩИТА РЕГИСТРАЦИИ: создание заведения только через RPC с проверкой промокода
-- Обойти защиту через прямой INSERT невозможно — anon INSERT закрыт.
-- =============================================================================

-- 1. Убираем anon INSERT на establishments (если ещё есть)
DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;

-- 2. RPC: регистрация компании только с валидным промокодом
-- Логика: проверить промокод → создать заведение → пометить промокод использованным
-- Всё в одной транзакции. Без валидного промокода заведение не создаётся.
CREATE OR REPLACE FUNCTION register_company_with_promo(
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
  -- 1. Валидация промокода (та же логика, что в check_promo_code / use_promo_code)
  SELECT * INTO v_row FROM promo_codes
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

  -- 2. Создание заведения (owner_id = NULL, владелец на следующем шаге)
  v_est_id := gen_random_uuid();
  INSERT INTO establishments (id, name, pin_code, address, default_currency, created_at, updated_at)
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    now(),
    now()
  );

  -- 3. Промокод помечаем использованным
  UPDATE promo_codes
  SET is_used = true, used_by_establishment_id = v_est_id, used_at = now()
  WHERE id = v_row.id;

  -- 4. Возврат созданного заведения
  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT id, name, pin_code, owner_id, address, phone, email, default_currency, created_at, updated_at
    FROM establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION register_company_with_promo IS 'Регистрация компании с обязательной проверкой промокода. Единственный способ создать новое заведение.';

GRANT EXECUTE ON FUNCTION register_company_with_promo(text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION register_company_with_promo(text, text, text, text) TO authenticated;
