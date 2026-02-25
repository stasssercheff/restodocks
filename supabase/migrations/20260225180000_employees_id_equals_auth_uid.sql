-- employees.id = auth.users.id: единый идентификатор.
-- Все входят только через Supabase Auth. employees.id станет auth.users.id.
--
-- ВНИМАНИЕ: Требует очистки данных (реальных пользователей пока нет).

-- 1. Обнулить owner_id в establishments
UPDATE establishments SET owner_id = NULL;

-- 2. Очистить employees (CASCADE затронет order_documents, inventory_documents, inventory_drafts, co_owner_invitations, password_reset_tokens)
TRUNCATE employees CASCADE;

-- 4. Удалить колонку auth_user_id
ALTER TABLE employees DROP COLUMN IF EXISTS auth_user_id;

-- 5. id больше не gen_random_uuid — всегда передаём auth.users.id при вставке
ALTER TABLE employees ALTER COLUMN id DROP DEFAULT;

-- 6. FK: employees.id должен существовать в auth.users
ALTER TABLE employees
  ADD CONSTRAINT fk_employees_auth
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 7. Обновить RLS: id = auth.uid() вместо auth_user_id = auth.uid()
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
CREATE POLICY "auth_select_employees" ON employees
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR establishment_id IN (SELECT establishment_id FROM employees e2 WHERE e2.id = auth.uid())
  );

DROP POLICY IF EXISTS "auth_insert_employees" ON employees;
CREATE POLICY "auth_insert_employees" ON employees
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "auth_update_employees" ON employees;
CREATE POLICY "auth_update_employees" ON employees
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (true);

DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
CREATE POLICY "auth_select_establishments" ON establishments
  FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
CREATE POLICY "auth_update_establishments" ON establishments
  FOR UPDATE TO authenticated
  USING (
    owner_id = auth.uid()
    OR id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  )
  WITH CHECK (true);

-- 8. co_owner_invitations: auth_user_id -> id
DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can view co-owner invitations" ON co_owner_invitations
  FOR SELECT USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );
DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can create co-owner invitations" ON co_owner_invitations
  FOR INSERT WITH CHECK (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );
DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can update co-owner invitations" ON co_owner_invitations
  FOR UPDATE USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

-- 9. product_price_history: auth_user_id -> id
DROP POLICY IF EXISTS "auth_select_product_price_history" ON product_price_history;
CREATE POLICY "auth_select_product_price_history" ON product_price_history
  FOR SELECT USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );
DROP POLICY IF EXISTS "auth_insert_product_price_history" ON product_price_history;
CREATE POLICY "auth_insert_product_price_history" ON product_price_history
  FOR INSERT WITH CHECK (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );

-- 10. send_registration_confirmed_email: auth_user_id -> id
CREATE OR REPLACE FUNCTION public.send_registration_confirmed_email()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  emp_email text;
  est_name text;
  anon_key text;
  func_url text := 'https://osglfptwbuqqmqunttha.supabase.co/functions/v1/send-registration-email';
BEGIN
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL AND NEW.email IS NOT NULL THEN
    SELECT e.email, est.name INTO emp_email, est_name
    FROM public.employees e
    LEFT JOIN public.establishments est ON est.id = e.establishment_id
    WHERE e.id = NEW.id
    LIMIT 1;
    IF emp_email IS NOT NULL THEN
      SELECT decrypted_secret INTO anon_key FROM vault.decrypted_secrets WHERE name = 'supabase_anon_key' LIMIT 1;
      IF anon_key IS NOT NULL AND anon_key != '' THEN
        PERFORM net.http_post(
          url := func_url,
          body := jsonb_build_object('type', 'registration_confirmed', 'to', emp_email, 'companyName', COALESCE(est_name, '')),
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || anon_key)
        );
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
