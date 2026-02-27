-- Делаем recipient_chef_id необязательным: чеклисты сохраняются для заведения без обязательного получателя.
ALTER TABLE checklist_submissions ALTER COLUMN recipient_chef_id DROP NOT NULL;

-- Restodocks использует anon-ключ без Supabase Auth — политики через anon роль
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_access" ON checklist_submissions;

-- Включаем RLS если ещё не включён
ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO anon USING (true) WITH CHECK (true);
