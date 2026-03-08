-- Филиалы заведений: parent_establishment_id, синхронизация номенклатуры и ТТК
-- Филиал наследует данные (номенклатура, ТТК ПФ, ТТК блюда) от основного заведения
-- Нельзя создать филиал филиала — только филиал основного заведения

-- === 1. parent_establishment_id в establishments ===
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS parent_establishment_id UUID REFERENCES establishments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_establishments_parent ON establishments(parent_establishment_id);

COMMENT ON COLUMN establishments.parent_establishment_id IS 'NULL = основное заведение, иначе = филиал указанного заведения';

-- Ограничение: родитель должен быть основным (не филиалом) — через триггер (CHECK не поддерживает подзапросы)
CREATE OR REPLACE FUNCTION check_parent_is_main()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.parent_establishment_id IS NULL THEN RETURN NEW; END IF;
  IF NOT EXISTS (SELECT 1 FROM establishments p WHERE p.id = NEW.parent_establishment_id AND p.parent_establishment_id IS NULL) THEN
    RAISE EXCEPTION 'parent_establishment_id must reference a main establishment (not a branch)';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_check_parent_is_main ON establishments;
CREATE TRIGGER trg_check_parent_is_main BEFORE INSERT OR UPDATE ON establishments FOR EACH ROW EXECUTE FUNCTION check_parent_is_main();

-- === 2. RPC: ID заведения для данных (филиал → родитель, основное → само) ===
CREATE OR REPLACE FUNCTION public.get_data_establishment_id(p_establishment_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT parent_establishment_id FROM establishments WHERE id = p_establishment_id),
    p_establishment_id
  );
$$;

COMMENT ON FUNCTION public.get_data_establishment_id IS 'Для филиала возвращает parent_id (данные читаем из родителя), для основного — self';

-- === 3. Обновить add_establishment_for_owner: параметр p_parent_establishment_id ===
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
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  -- Если филиал: проверяем parent — должен существовать, принадлежать владельцу, быть основным
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

GRANT EXECUTE ON FUNCTION public.add_establishment_for_owner(text, text, text, text, text, uuid) TO authenticated;

-- === 4. RPC: филиалы данного заведения (для шефа — фильтр по филиалам) ===
CREATE OR REPLACE FUNCTION public.get_branches_for_establishment(p_establishment_id uuid)
RETURNS SETOF establishments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT e.* FROM establishments e
  WHERE e.parent_establishment_id = p_establishment_id
  ORDER BY e.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_branches_for_establishment TO authenticated;
