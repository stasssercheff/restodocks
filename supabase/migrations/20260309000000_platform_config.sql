-- Таблица настроек платформы (ключ-значение). Админ редактирует через API.
CREATE TABLE IF NOT EXISTS public.platform_config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE platform_config ENABLE ROW LEVEL SECURITY;

-- Только чтение для anon и authenticated (приложение читает лимиты)
CREATE POLICY "platform_config_select_all"
  ON platform_config FOR SELECT
  TO anon, authenticated
  USING (true);

-- Только service_role может писать (админ через API)
-- Нет INSERT/UPDATE для anon/auth

COMMENT ON TABLE platform_config IS 'Настройки платформы. Редактируются только из админки.';

-- Дефолтное значение: максимум дополнительных заведений на одного владельца (не считая первое)
INSERT INTO platform_config (key, value)
VALUES ('max_establishments_per_owner', '5')
ON CONFLICT (key) DO NOTHING;

-- RPC: получить значение настройки (для чтения из приложения)
CREATE OR REPLACE FUNCTION public.get_platform_config(p_key text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT value FROM platform_config WHERE key = p_key LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_platform_config IS 'Читает значение настройки платформы по ключу. NULL если ключа нет.';

GRANT EXECUTE ON FUNCTION public.get_platform_config TO anon, authenticated;

-- Обновить add_establishment_for_owner: проверка лимита дополнительных заведений
CREATE OR REPLACE FUNCTION public.add_establishment_for_owner(
  p_name text,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_pin_code text DEFAULT NULL,
  p_parent_establishment_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_est jsonb;
  v_now timestamptz := now();
  v_current_count int;
  v_max int;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  -- Лимит: максимум ДОПОЛНИТЕЛЬНЫХ заведений (первое не в счёт). v_max = допустимо дополнительных.
  SELECT COUNT(*)::int INTO v_current_count
  FROM establishments WHERE owner_id = v_owner_id;

  v_max := (get_platform_config('max_establishments_per_owner'))::text::int;
  IF v_max IS NULL OR v_max < 0 THEN v_max := 999; END IF;
  -- Дополнительных = текущих - 1 (первое заведение). Лимит: дополнительных < v_max.
  IF (v_current_count - 1) >= v_max THEN
    RAISE EXCEPTION 'add_establishment_for_owner: limit reached, max % additional establishments per owner', v_max;
  END IF;

  -- Если филиал: проверяем parent
  IF p_parent_establishment_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM establishments
      WHERE id = p_parent_establishment_id
        AND owner_id = v_owner_id
        AND parent_establishment_id IS NULL
    ) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: parent must be your main establishment';
    END IF;
  END IF;

  IF p_pin_code IS NULL OR trim(p_pin_code) = '' THEN
    LOOP
      v_pin := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));
      IF NOT EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_pin := upper(trim(p_pin_code));
    IF EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: pin_code already exists';
    END IF;
  END IF;

  INSERT INTO establishments (name, pin_code, owner_id, address, phone, email, parent_establishment_id, created_at, updated_at)
  VALUES (
    trim(p_name), v_pin, v_owner_id,
    nullif(trim(p_address), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    p_parent_establishment_id,
    v_now, v_now
  )
  RETURNING to_jsonb(establishments.*) INTO v_est;

  RETURN v_est;
END;
$$;
