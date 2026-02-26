-- checklist_submissions: гарантируем колонку checklist_name, RLS
-- (если таблица не существует — создайте её из supabase_migration_checklist_submissions.sql)
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS checklist_name TEXT DEFAULT '';

ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;

CREATE POLICY "anon_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- checklist_drafts: добавляем auth-политику (anon уже есть в 20260226100000)
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
CREATE POLICY "auth_checklist_drafts_all" ON checklist_drafts
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
