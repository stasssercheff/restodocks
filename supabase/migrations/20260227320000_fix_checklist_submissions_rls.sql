-- Fix: пересоздаём все политики RLS для checklist_submissions
-- Причина: при вставке через anon-ключ без Supabase Auth срабатывала
-- старая политика с auth.uid(), что давало 42501.

ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;

-- Удаляем все возможные варианты старых политик
DROP POLICY IF EXISTS "anon_checklist_submissions_all"        ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all"        ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_access"          ON checklist_submissions;
DROP POLICY IF EXISTS "allow_anon_insert"                     ON checklist_submissions;
DROP POLICY IF EXISTS "allow_anon_select"                     ON checklist_submissions;
DROP POLICY IF EXISTS "allow_all"                             ON checklist_submissions;

-- Единая открытая политика для anon (приложение работает без Supabase Auth)
CREATE POLICY "anon_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- Политика для authenticated (на случай будущего использования)
CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
