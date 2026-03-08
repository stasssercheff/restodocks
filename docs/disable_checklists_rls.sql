-- Отключить RLS для чеклистов — чеклисты снова будут сохраняться.
-- Доступ контролируется Supabase Auth + anon key (без дополнительных политик).

ALTER TABLE checklists DISABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items DISABLE ROW LEVEL SECURITY;
