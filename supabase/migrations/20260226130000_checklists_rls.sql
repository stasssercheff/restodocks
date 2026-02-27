-- RLS политики для checklists и checklist_items.
-- Приложение использует anon (как inventory_documents, order_documents).

ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;

-- checklists: anon-доступ
DROP POLICY IF EXISTS "checklists_establishment_access" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_select" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_insert" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_update" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_delete" ON checklists;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklists' AND policyname = 'anon_checklists_all') THEN
    CREATE POLICY "anon_checklists_all" ON checklists FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

-- checklist_items: anon-доступ
DROP POLICY IF EXISTS "checklist_items_checklist_access" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_select" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_insert" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_update" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_delete" ON checklist_items;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklist_items' AND policyname = 'anon_checklist_items_all') THEN
    CREATE POLICY "anon_checklist_items_all" ON checklist_items FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

-- authenticated: на случай если приложение использует Supabase Auth
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklists' AND policyname = 'auth_checklists_all') THEN
    CREATE POLICY "auth_checklists_all" ON checklists FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklist_items' AND policyname = 'auth_checklist_items_all') THEN
    CREATE POLICY "auth_checklist_items_all" ON checklist_items FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;
