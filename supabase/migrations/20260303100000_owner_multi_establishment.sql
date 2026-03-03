-- Owner-centric model: владелец — ключевое звено, может иметь несколько заведений.
-- 1. RPC добавления заведения существующим владельцем (без регистрации владельца)
-- 2. RPC получения списка заведений владельца
-- 3. RLS: владелец видит данные всех своих заведений (owner_id = auth.uid())
-- 4. owner_access_level для co-owner: view_only при >1 заведении у пригласившего

-- === 1. owner_access_level в employees (co-owner view-only) ===
ALTER TABLE employees ADD COLUMN IF NOT EXISTS owner_access_level TEXT DEFAULT 'full' CHECK (owner_access_level IN ('full', 'view_only'));

COMMENT ON COLUMN employees.owner_access_level IS 'full = полный доступ, view_only = только просмотр (co-owner при >1 заведении)';

-- === 2. RPC: add_establishment_for_owner ===
-- Добавление заведения существующим владельцем. Без регистрации владельца.
CREATE OR REPLACE FUNCTION public.add_establishment_for_owner(
  p_name text,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_pin_code text DEFAULT NULL
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

  -- Проверка: пользователь — владелец хотя бы одного заведения
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  -- Генерация уникального PIN, если не передан
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

  INSERT INTO establishments (name, pin_code, owner_id, address, phone, email, created_at, updated_at)
  VALUES (
    trim(p_name), v_pin, v_owner_id,
    nullif(trim(p_address), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    v_now, v_now
  )
  RETURNING to_jsonb(establishments.*) INTO v_est;

  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.add_establishment_for_owner IS 'Добавление заведения существующим владельцем. Без регистрации владельца.';

GRANT EXECUTE ON FUNCTION public.add_establishment_for_owner TO authenticated;

-- === 3. RPC: get_establishments_for_owner ===
CREATE OR REPLACE FUNCTION public.get_establishments_for_owner()
RETURNS SETOF establishments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT e.* FROM establishments e
  WHERE e.owner_id = auth.uid()
  ORDER BY e.created_at;
$$;

COMMENT ON FUNCTION public.get_establishments_for_owner IS 'Список заведений владельца (owner_id = auth.uid)';

GRANT EXECUTE ON FUNCTION public.get_establishments_for_owner TO authenticated;

-- === 3b. Helpers для RLS (нужны до создания политик) ===
CREATE OR REPLACE FUNCTION public.is_current_user_view_only_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE id = auth.uid()
      AND 'owner' = ANY(roles)
      AND coalesce(owner_access_level, 'full') = 'view_only'
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_establishment_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM establishments WHERE owner_id = auth.uid()
  UNION
  SELECT establishment_id FROM employees WHERE id = auth.uid();
$$;

-- === 4. Обновить create_owner_employee: параметр p_owner_access_level ===
CREATE OR REPLACE FUNCTION public.create_owner_employee(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner'],
  p_owner_access_level text DEFAULT 'full'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
  v_access text := coalesce(nullif(trim(p_owner_access_level), ''), 'full');
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN
    v_access := 'full';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_exists;

  IF NOT v_exists THEN
    RAISE EXCEPTION 'create_owner_employee: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_owner_employee: establishment % not found', p_establishment_id;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    'management', NULL, p_roles, p_establishment_id, v_personal_pin,
    'ru', true, true, v_access, v_now, v_now
  );

  UPDATE establishments SET owner_id = p_auth_user_id, updated_at = v_now
  WHERE id = p_establishment_id;

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           owner_access_level, created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

-- Backfill owner_access_level для существующих записей (primary owner = full)
UPDATE employees SET owner_access_level = 'full' WHERE owner_access_level IS NULL AND 'owner' = ANY(roles);

-- === 5. create_employee_for_company: владелец может добавлять сотрудников в любое своё заведение ===
CREATE OR REPLACE FUNCTION public.create_employee_for_company(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[],
  p_owner_access_level text DEFAULT 'full'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_is_owner boolean;
  v_auth_exists boolean;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
  v_access text := coalesce(nullif(trim(p_owner_access_level), ''), 'full');
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN
    v_access := 'full';
  END IF;

  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'create_employee_for_company: must be authenticated';
  END IF;

  -- Владелец: либо владеет заведением (owner_id), либо его employee.establishment_id = p_establishment_id
  SELECT EXISTS (
    SELECT 1 FROM establishments e
    WHERE e.id = p_establishment_id
      AND (e.owner_id = v_caller_id
           OR EXISTS (
             SELECT 1 FROM employees emp
             WHERE emp.id = v_caller_id
               AND emp.establishment_id = p_establishment_id
               AND 'owner' = ANY(emp.roles)
               AND emp.is_active = true
           ))
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'create_employee_for_company: only owner can add employees';
  END IF;

  IF is_current_user_view_only_owner() THEN
    RAISE EXCEPTION 'create_employee_for_company: view-only owner cannot add employees';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;

  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_for_company: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_employee_for_company: establishment % not found', p_establishment_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_for_company: email already taken in establishment';
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  -- owner роль: вставляем с owner_access_level
  IF 'owner' = ANY(p_roles) THEN
    INSERT INTO employees (
      id, full_name, surname, email, password_hash,
      department, section, roles, establishment_id, personal_pin,
      preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
    )     VALUES (
      p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
      trim(p_email), NULL,
      COALESCE(NULLIF(trim(p_department), ''), 'management'),
      nullif(trim(p_section), ''),
      p_roles, p_establishment_id, v_personal_pin,
      'ru', true, true, v_access, v_now, v_now
    );
    -- Co-owner: не обновляем owner_id (основной владелец уже задан)
  ELSE
    INSERT INTO employees (
      id, full_name, surname, email, password_hash,
      department, section, roles, establishment_id, personal_pin,
      preferred_language, is_active, data_access_enabled, created_at, updated_at
    ) VALUES (
      p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
      trim(p_email), NULL,
      COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
      nullif(trim(p_section), ''),
      p_roles, p_establishment_id, v_personal_pin,
      'ru', true, false, v_now, v_now
    );
  END IF;

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           owner_access_level, created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

-- === 6. co_owner_invitations: is_view_only_owner ===
ALTER TABLE co_owner_invitations ADD COLUMN IF NOT EXISTS is_view_only_owner boolean DEFAULT false;

-- co_owner_invitations: view_only не может создавать приглашения; владелец видит приглашения всех своих заведений
DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can view co-owner invitations" ON co_owner_invitations
  FOR SELECT USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "Owners can create co-owner invitations" ON co_owner_invitations
  FOR INSERT WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND NOT is_current_user_view_only_owner()
  );
CREATE POLICY "Owners can update co-owner invitations" ON co_owner_invitations
  FOR UPDATE USING (establishment_id IN (SELECT current_user_establishment_ids()));

-- === 6b. RPC: create_co_owner_from_invitation ===
-- Co-owner создаёт свою запись сотрудника по принятому приглашению (session = новый юзер)
CREATE OR REPLACE FUNCTION public.create_co_owner_from_invitation(
  p_invitation_token text,
  p_full_name text,
  p_surname text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv record;
  v_access text;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'create_co_owner_from_invitation: must be authenticated';
  END IF;

  SELECT inv.*, e.id as est_id, e.name as est_name, e.pin_code as est_pin, e.default_currency as est_currency
  INTO v_inv
  FROM co_owner_invitations inv
  JOIN establishments e ON e.id = inv.establishment_id
  WHERE inv.invitation_token = p_invitation_token
    AND inv.status = 'accepted'
    AND LOWER(inv.invited_email) = LOWER((SELECT email FROM auth.users WHERE id = auth.uid()));

  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'create_co_owner_from_invitation: invalid or expired invitation';
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'create_co_owner_from_invitation: employee already exists';
  END IF;

  v_access := CASE WHEN coalesce(v_inv.is_view_only_owner, false) THEN 'view_only' ELSE 'full' END;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  )
  SELECT
    auth.uid(), trim(p_full_name), nullif(trim(p_surname), ''),
    au.email, NULL,
    'management', NULL, ARRAY['owner'], v_inv.establishment_id, v_personal_pin,
    'ru', true, true, v_access, v_now, v_now
  FROM auth.users au WHERE au.id = auth.uid();

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           owner_access_level, created_at, updated_at
    FROM employees WHERE id = auth.uid()
  ) r;

  RETURN v_emp;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_co_owner_from_invitation TO authenticated;

-- RPC для загрузки приглашения по токену (anon — для экрана регистрации до входа)
CREATE OR REPLACE FUNCTION public.get_co_owner_invitation_by_token(p_token text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT to_jsonb(r) FROM (
    SELECT inv.*, jsonb_build_object(
      'id', e.id, 'name', e.name, 'pin_code', e.pin_code,
      'owner_id', e.owner_id, 'default_currency', e.default_currency,
      'created_at', e.created_at, 'updated_at', e.updated_at
    ) as establishments
    FROM co_owner_invitations inv
    JOIN establishments e ON e.id = inv.establishment_id
    WHERE inv.invitation_token = p_token
      AND inv.status IN ('pending', 'accepted')
      AND (inv.expires_at IS NULL OR inv.expires_at > now())
  ) r;
$$;

GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token TO anon;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token TO authenticated;

-- === 8. RLS: владелец — доступ ко всем своим заведениям ===
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
CREATE POLICY "auth_select_employees" ON employees
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR establishment_id IN (SELECT current_user_establishment_ids())
  );

DROP POLICY IF EXISTS "auth_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_delete_establishment_products" ON establishment_products;
CREATE POLICY "auth_select_establishment_products" ON establishment_products FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_insert_establishment_products" ON establishment_products FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_update_establishment_products" ON establishment_products FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_delete_establishment_products" ON establishment_products FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_inventory_documents_select" ON inventory_documents;
DROP POLICY IF EXISTS "auth_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_select" ON inventory_documents FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
    OR recipient_chef_id = auth.uid()
  );
CREATE POLICY "auth_inventory_documents_insert" ON inventory_documents FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_order_documents_select" ON order_documents;
DROP POLICY IF EXISTS "auth_order_documents_insert" ON order_documents;
CREATE POLICY "auth_order_documents_select" ON order_documents FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_order_documents_insert" ON order_documents FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_inventory_drafts" ON inventory_drafts;
DROP POLICY IF EXISTS "auth_inventory_drafts_select" ON inventory_drafts;
DROP POLICY IF EXISTS "auth_inventory_drafts_insert" ON inventory_drafts;
DROP POLICY IF EXISTS "auth_inventory_drafts_update" ON inventory_drafts;
CREATE POLICY "auth_inventory_drafts_select" ON inventory_drafts FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_inventory_drafts_insert" ON inventory_drafts FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_inventory_drafts_update" ON inventory_drafts FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_select_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_insert_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_update_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_delete_tech_cards" ON tech_cards;
CREATE POLICY "auth_select_tech_cards" ON tech_cards FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_insert_tech_cards" ON tech_cards FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_update_tech_cards" ON tech_cards FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_delete_tech_cards" ON tech_cards FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
CREATE POLICY "auth_select_establishments" ON establishments FOR SELECT TO authenticated
  USING (id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_update_establishments" ON establishments FOR UPDATE TO authenticated
  USING (id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (true);

-- checklists, checklist_items — владелец видит все свои
DROP POLICY IF EXISTS "auth_checklists_select" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_insert" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_update" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_delete" ON checklists;
CREATE POLICY "auth_checklists_select" ON checklists FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_checklists_insert" ON checklists FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklists_update" ON checklists FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklists_delete" ON checklists FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_checklist_items_select" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_insert" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_update" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_delete" ON checklist_items;
CREATE POLICY "auth_checklist_items_select" ON checklist_items FOR SELECT TO authenticated
  USING (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())));
CREATE POLICY "auth_checklist_items_insert" ON checklist_items FOR INSERT TO authenticated
  WITH CHECK (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_items_update" ON checklist_items FOR UPDATE TO authenticated
  USING (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner())
  WITH CHECK (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_items_delete" ON checklist_items FOR DELETE TO authenticated
  USING (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner());

-- checklist_drafts, checklist_submissions, schedule, order_list
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
CREATE POLICY "auth_checklist_drafts_select" ON checklist_drafts FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_checklist_drafts_insert" ON checklist_drafts FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_drafts_update" ON checklist_drafts FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_drafts_delete" ON checklist_drafts FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;
CREATE POLICY "auth_checklist_submissions_select" ON checklist_submissions FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
    OR recipient_chef_id = auth.uid()
  );
CREATE POLICY "auth_checklist_submissions_insert" ON checklist_submissions FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_submissions_update" ON checklist_submissions FOR UPDATE TO authenticated
  USING (
    (establishment_id IN (SELECT current_user_establishment_ids()) OR recipient_chef_id = auth.uid())
    AND NOT is_current_user_view_only_owner()
  )
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_submissions_delete" ON checklist_submissions FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_schedule_select" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_insert" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_update" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_select" ON establishment_schedule_data FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_schedule_insert" ON establishment_schedule_data FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_schedule_update" ON establishment_schedule_data FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));

DROP POLICY IF EXISTS "auth_order_list_select" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_insert" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_update" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_select" ON establishment_order_list_data FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_order_list_insert" ON establishment_order_list_data FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_order_list_update" ON establishment_order_list_data FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));

-- product_price_history
DROP POLICY IF EXISTS "auth_select_product_price_history" ON product_price_history;
DROP POLICY IF EXISTS "auth_insert_product_price_history" ON product_price_history;
CREATE POLICY "auth_select_product_price_history" ON product_price_history FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_insert_product_price_history" ON product_price_history FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));
