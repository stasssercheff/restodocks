-- checklist_submissions: колонка section (Postgrest schema cache error)
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS section TEXT;
