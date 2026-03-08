-- Двухфазная регистрация владельца: сохраняем данные до confirm email, создаём employee после.
-- Решает race: auth.users не виден сразу после signUp, FK fk_employees_auth падает.

CREATE TABLE IF NOT EXISTS public.pending_owner_registrations (
  auth_user_id uuid PRIMARY KEY,
  establishment_id uuid NOT NULL REFERENCES establishments(id),
  full_name text NOT NULL,
  surname text,
  email text NOT NULL,
  roles text[] NOT NULL DEFAULT ARRAY['owner'],
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE pending_owner_registrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_insert_pending_owner" ON pending_owner_registrations;
DROP POLICY IF EXISTS "authenticated_select_own_pending" ON pending_owner_registrations;

-- anon может вставить (после signUp, до confirm)
CREATE POLICY "anon_insert_pending_owner" ON pending_owner_registrations
  FOR INSERT TO anon WITH CHECK (true);

-- authenticated не видит чужие (для complete нужен RPC)
CREATE POLICY "authenticated_select_own_pending" ON pending_owner_registrations
  FOR SELECT TO authenticated USING (auth_user_id = auth.uid());

-- RPC: сохранить pending (anon, после signUp)
CREATE OR REPLACE FUNCTION public.save_pending_owner_registration(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner']
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'establishment not found';
  END IF;
  INSERT INTO pending_owner_registrations (auth_user_id, establishment_id, full_name, surname, email, roles)
  VALUES (p_auth_user_id, p_establishment_id, trim(p_full_name), nullif(trim(p_surname), ''), trim(p_email), p_roles)
  ON CONFLICT (auth_user_id) DO UPDATE SET
    establishment_id = EXCLUDED.establishment_id,
    full_name = EXCLUDED.full_name,
    surname = EXCLUDED.surname,
    email = EXCLUDED.email,
    roles = EXCLUDED.roles,
    created_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration TO anon;
GRANT EXECUTE ON FUNCTION public.save_pending_owner_registration TO authenticated;

-- RPC: завершить регистрацию (authenticated, после confirm — user есть в auth.users)
CREATE OR REPLACE FUNCTION public.complete_pending_owner_registration()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row pending_owner_registrations%rowtype;
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'must be authenticated';
  END IF;

  SELECT * INTO v_row FROM pending_owner_registrations WHERE auth_user_id = auth.uid();
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  ) VALUES (
    auth.uid(), trim(v_row.full_name), v_row.surname, trim(v_row.email), NULL,
    'management', NULL, v_row.roles, v_row.establishment_id, v_personal_pin,
    'ru', true, true, 'full', v_now, v_now
  );

  UPDATE establishments SET owner_id = auth.uid(), updated_at = v_now WHERE id = v_row.establishment_id;

  DELETE FROM pending_owner_registrations WHERE auth_user_id = auth.uid();

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           owner_access_level, created_at, updated_at
    FROM employees WHERE id = auth.uid()
  ) r;

  RETURN jsonb_build_object(
    'employee', v_emp,
    'establishment', (SELECT to_jsonb(e) FROM establishments e WHERE id = v_row.establishment_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_pending_owner_registration TO authenticated;
