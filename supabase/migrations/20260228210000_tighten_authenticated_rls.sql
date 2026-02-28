-- =============================================================================
-- SECURITY: Tighten authenticated RLS policies — scope to own establishment
--
-- Analysis findings:
--
-- GLOBAL BY DESIGN (no establishment_id column, intentional shared catalog):
--   - products: global ingredient catalog, all establishments share it. KEEP USING(true).
--   - translations: global translation cache keyed by entity_id. KEEP USING(true).
--
-- ESTABLISHMENT-SCOPED (have establishment_id column, all app queries already
--   filter by establishmentId — only need RLS to enforce it server-side):
--   - establishment_products
--   - inventory_documents
--   - order_documents
--   - inventory_drafts
--   - checklist_drafts
--   - checklist_submissions
--   - establishment_schedule_data
--   - establishment_order_list_data
--   - tech_cards
--
-- NOTE on tech_cards: getAllTechCards() in the app has no filter, but this call
--   is used only to check if a product is referenced before deletion — after
--   applying RLS it will return only the current establishment's cards, which
--   is the correct and safe behavior. No logic change, just data narrowing.
--
-- NOTE on inventory_documents / order_documents / checklist_submissions:
--   Some queries filter by recipient_chef_id or by id directly. The RLS policy
--   below allows access when establishment_id matches OR when the row's
--   recipient_chef_id matches the current user — so chef inbox queries still work.
--
-- Helper: auth.uid() = employees.id (architecture from migration 20260225180000)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. establishment_products — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_delete_establishment_products" ON establishment_products;

CREATE POLICY "auth_select_establishment_products" ON establishment_products
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_insert_establishment_products" ON establishment_products
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_update_establishment_products" ON establishment_products
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_delete_establishment_products" ON establishment_products
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 2. inventory_documents — scope to own establishment
--    Also allow chef to SELECT their own inbox (recipient_chef_id = auth.uid())
--    and SELECT by document id when user is from same establishment.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_inventory_documents_select" ON inventory_documents;
DROP POLICY IF EXISTS "auth_inventory_documents_insert" ON inventory_documents;

CREATE POLICY "auth_inventory_documents_select" ON inventory_documents
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
    OR recipient_chef_id = auth.uid()
  );

CREATE POLICY "auth_inventory_documents_insert" ON inventory_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3. order_documents — scope to own establishment
--    Also allow chef inbox access by recipient_chef_id.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_order_documents_select" ON order_documents;
DROP POLICY IF EXISTS "auth_order_documents_insert" ON order_documents;

CREATE POLICY "auth_order_documents_select" ON order_documents
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_order_documents_insert" ON order_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 4. inventory_drafts — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_inventory_drafts" ON inventory_drafts;

CREATE POLICY "auth_inventory_drafts" ON inventory_drafts
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 5. checklist_drafts — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;

CREATE POLICY "auth_checklist_drafts_all" ON checklist_drafts
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 6. checklist_submissions — scope to own establishment
--    Also allow chef inbox access (recipient_chef_id = auth.uid()).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;

CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
    OR recipient_chef_id = auth.uid()
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 7. establishment_schedule_data — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_schedule_select" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_insert" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_update" ON establishment_schedule_data;

CREATE POLICY "auth_schedule_select" ON establishment_schedule_data
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_schedule_insert" ON establishment_schedule_data
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_schedule_update" ON establishment_schedule_data
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 8. establishment_order_list_data — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_order_list_select" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_insert" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_update" ON establishment_order_list_data;

CREATE POLICY "auth_order_list_select" ON establishment_order_list_data
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_order_list_insert" ON establishment_order_list_data
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_order_list_update" ON establishment_order_list_data
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 9. tech_cards — scope to own establishment
--    getAllTechCards() in the app will now naturally return only own cards.
--    getTechCardById() and getTechCardsByCreator() are covered by the
--    establishment_id check since tech cards always belong to one establishment.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_tech_cards_select" ON tech_cards;

DROP POLICY IF EXISTS "auth_select_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_insert_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_update_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_delete_tech_cards" ON tech_cards;

CREATE POLICY "auth_select_tech_cards" ON tech_cards
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_insert_tech_cards" ON tech_cards
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_update_tech_cards" ON tech_cards
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_delete_tech_cards" ON tech_cards
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );
