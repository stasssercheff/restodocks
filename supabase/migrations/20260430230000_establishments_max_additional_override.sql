-- Переопределение лимита дополнительных заведений на уровне заведения (админка).
-- Если задано хотя бы на одном заведении владельца, для аккаунта действует MIN(все ненулевые переопределения) —
-- так и «расширение», и «снижение» относительно глобальной настройки platform_config.

ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS max_additional_establishments_override integer;

COMMENT ON COLUMN public.establishments.max_additional_establishments_override IS
  'Админ: макс. дополнительных заведений для владельца (как max_establishments_per_owner). NULL = общий лимит из platform_config.';

-- Только service_role (админ API) может менять колонку; пользователи сохраняют старое значение.
CREATE OR REPLACE FUNCTION public.establishments_preserve_max_additional_override()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := coalesce(auth.jwt() ->> 'role', '');
BEGIN
  IF v_role = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.max_additional_establishments_override := NULL;
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.max_additional_establishments_override := OLD.max_additional_establishments_override;
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_establishments_preserve_max_additional_override ON public.establishments;
CREATE TRIGGER tr_establishments_preserve_max_additional_override
  BEFORE INSERT OR UPDATE ON public.establishments
  FOR EACH ROW
  EXECUTE FUNCTION public.establishments_preserve_max_additional_override();

COMMENT ON FUNCTION public.establishments_preserve_max_additional_override IS
  'Запрещает клиентам менять max_additional_establishments_override; только service_role.';

-- Эффективный лимит для текущего владельца (auth.uid())
CREATE OR REPLACE FUNCTION public.get_effective_max_additional_establishments_for_owner()
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid := auth.uid();
  v_global int;
  v_min_override int;
BEGIN
  IF v_owner_id IS NULL THEN
    RETURN 5;
  END IF;

  v_global := (get_platform_config('max_establishments_per_owner'))::text::int;
  IF v_global IS NULL OR v_global < 0 THEN
    v_global := 999;
  END IF;

  SELECT MIN(max_additional_establishments_override)::int
  INTO v_min_override
  FROM public.establishments
  WHERE owner_id = v_owner_id
    AND max_additional_establishments_override IS NOT NULL;

  RETURN COALESCE(v_min_override, v_global);
END;
$$;

COMMENT ON FUNCTION public.get_effective_max_additional_establishments_for_owner IS
  'Максимум дополнительных заведений для текущего владельца: min(переопределения по заведениям) или глобальный лимит.';

GRANT EXECUTE ON FUNCTION public.get_effective_max_additional_establishments_for_owner() TO anon, authenticated;

-- add_establishment_for_owner: учитывать переопределения
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
  v_min_override int;
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  SELECT COUNT(*)::int INTO v_current_count
  FROM establishments WHERE owner_id = v_owner_id;

  v_max := (get_platform_config('max_establishments_per_owner'))::text::int;
  IF v_max IS NULL OR v_max < 0 THEN v_max := 999; END IF;

  SELECT MIN(max_additional_establishments_override)::int
  INTO v_min_override
  FROM establishments
  WHERE owner_id = v_owner_id
    AND max_additional_establishments_override IS NOT NULL;

  v_max := COALESCE(v_min_override, v_max);

  IF (v_current_count - 1) >= v_max THEN
    RAISE EXCEPTION 'add_establishment_for_owner: limit reached, max % additional establishments per owner', v_max;
  END IF;

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
