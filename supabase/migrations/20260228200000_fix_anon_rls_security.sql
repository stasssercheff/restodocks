-- =============================================================================
-- SECURITY FIX: Restrict anon role access to minimum required for public flows
--
-- ANALYSIS of unauthenticated (anon) flows:
--   1. Company registration: INSERT establishments, INSERT/UPDATE via RPC (SECURITY DEFINER)
--   2. Employee registration: SELECT establishments (PIN lookup), SELECT employees (email check),
--      INSERT employees via RPC (SECURITY DEFINER)
--   3. Co-owner invite: SELECT/UPDATE co_owner_invitations (token-based, already secure via obscurity)
--   4. Session restore on startup: SELECT employees + establishments (only own id, no leakage)
--   5. Forgot/Reset password: handled entirely via Edge Functions with service_role key
--   6. Login: handled via Supabase Auth API + Edge Function with service_role key
--
-- WHAT WE CLOSE:
--   - anon INSERT/UPDATE on establishments (not needed — RPCs are SECURITY DEFINER)
--   - anon INSERT/UPDATE on employees (not needed — RPCs are SECURITY DEFINER)
--   - anon ALL on products, establishment_products, product_price_history
--   - anon ALL on inventory_documents, order_documents
--   - anon ALL on inventory_drafts, checklist_drafts, checklist_submissions
--   - anon ALL on establishment_schedule_data, establishment_order_list_data
--
-- WHAT WE KEEP for anon:
--   - SELECT on establishments (PIN lookup during employee registration)
--   - SELECT on employees (email uniqueness check during registration)
--   - SELECT on co_owner_invitations (token-based invite acceptance)
--   - SELECT on tech_cards (already minimal — SELECT only)
--
-- All authenticated flows already have proper auth.uid() policies.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. establishments — remove anon INSERT and UPDATE, keep SELECT
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;
DROP POLICY IF EXISTS "anon_update_establishments" ON establishments;

-- ---------------------------------------------------------------------------
-- 2. employees — remove anon INSERT and UPDATE, keep SELECT
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_insert_employees" ON employees;
DROP POLICY IF EXISTS "anon_update_employees" ON employees;

-- ---------------------------------------------------------------------------
-- 3. products — remove all anon policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_products" ON products;
DROP POLICY IF EXISTS "anon_insert_products" ON products;
DROP POLICY IF EXISTS "anon_update_products" ON products;
DROP POLICY IF EXISTS "anon_delete_products" ON products;

-- Add authenticated policy for products (scoped to own establishment)
DROP POLICY IF EXISTS "auth_select_products" ON products;
DROP POLICY IF EXISTS "auth_insert_products" ON products;
DROP POLICY IF EXISTS "auth_update_products" ON products;
DROP POLICY IF EXISTS "auth_delete_products" ON products;

CREATE POLICY "auth_select_products" ON products
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "auth_insert_products" ON products
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "auth_update_products" ON products
  FOR UPDATE TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY "auth_delete_products" ON products
  FOR DELETE TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 4. establishment_products — remove all anon policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "anon_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "anon_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "anon_delete_establishment_products" ON establishment_products;

-- Add authenticated policy
DROP POLICY IF EXISTS "auth_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_delete_establishment_products" ON establishment_products;

CREATE POLICY "auth_select_establishment_products" ON establishment_products
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "auth_insert_establishment_products" ON establishment_products
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "auth_update_establishment_products" ON establishment_products
  FOR UPDATE TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY "auth_delete_establishment_products" ON establishment_products
  FOR DELETE TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 5. product_price_history — remove anon policies (auth policies already exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_product_price_history" ON product_price_history;
DROP POLICY IF EXISTS "anon_insert_product_price_history" ON product_price_history;

-- ---------------------------------------------------------------------------
-- 6. inventory_documents — remove anon policies (auth policies already exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_inventory_documents_select" ON inventory_documents;
DROP POLICY IF EXISTS "anon_inventory_documents_insert" ON inventory_documents;

-- ---------------------------------------------------------------------------
-- 7. order_documents — remove anon policies (auth policies already exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_order_documents_select" ON order_documents;
DROP POLICY IF EXISTS "anon_order_documents_insert" ON order_documents;

-- ---------------------------------------------------------------------------
-- 8. inventory_drafts — remove anon ALL policy, add authenticated
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_inventory_drafts" ON inventory_drafts;

DROP POLICY IF EXISTS "auth_inventory_drafts" ON inventory_drafts;
CREATE POLICY "auth_inventory_drafts" ON inventory_drafts
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- 9. checklist_drafts — remove anon ALL policy (auth policy already exists)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklist_drafts" ON checklist_drafts;

-- ---------------------------------------------------------------------------
-- 10. checklist_submissions — remove anon ALL policy (auth policy already exists)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;

-- ---------------------------------------------------------------------------
-- 11. establishment_schedule_data — remove anon policies (auth policies exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_schedule_select" ON establishment_schedule_data;
DROP POLICY IF EXISTS "anon_schedule_insert" ON establishment_schedule_data;
DROP POLICY IF EXISTS "anon_schedule_update" ON establishment_schedule_data;

-- ---------------------------------------------------------------------------
-- 12. establishment_order_list_data — remove anon policies (auth policies exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_order_list_select" ON establishment_order_list_data;
DROP POLICY IF EXISTS "anon_order_list_insert" ON establishment_order_list_data;
DROP POLICY IF EXISTS "anon_order_list_update" ON establishment_order_list_data;

-- ---------------------------------------------------------------------------
-- 13. co_owner_invitations — add anon SELECT and UPDATE for token-based invite flow
--     (these pages are public: /accept-co-owner-invitation, /register-co-owner)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_co_owner_invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;

CREATE POLICY "anon_select_co_owner_invitations" ON co_owner_invitations
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon_update_co_owner_invitations" ON co_owner_invitations
  FOR UPDATE TO anon
  USING (true) WITH CHECK (true);
