-- Восстановить anon-доступ к чеклистам для legacy-логина (как было на Vercel).
-- Без этого сохранение (UPDATE + checklist_items) не работает при auth: false.

-- checklists: anon может делать всё
DROP POLICY IF EXISTS "auth_checklists_select" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_insert" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_update" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_delete" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_all" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_all" ON checklists;
CREATE POLICY "anon_checklists_all" ON checklists FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "auth_checklists_all" ON checklists FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- checklist_items: anon может делать всё
DROP POLICY IF EXISTS "auth_checklist_items_select" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_insert" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_update" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_delete" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_all" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_all" ON checklist_items;
CREATE POLICY "anon_checklist_items_all" ON checklist_items FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "auth_checklist_items_all" ON checklist_items FOR ALL TO authenticated USING (true) WITH CHECK (true);
