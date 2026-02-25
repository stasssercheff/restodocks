-- Отправленные заполненные чеклисты: шеф и су-шеф видят их во входящих.
-- Один ряд на получателя (recipient_chef_id), чтобы RLS работал.
-- Выполните в SQL Editor Supabase.

CREATE TABLE IF NOT EXISTS checklist_submissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  submitted_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  checklist_name TEXT NOT NULL,
  section TEXT,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checklist_submissions_establishment ON checklist_submissions(establishment_id);
CREATE INDEX IF NOT EXISTS idx_checklist_submissions_recipient ON checklist_submissions(recipient_chef_id);
CREATE INDEX IF NOT EXISTS idx_checklist_submissions_created_at ON checklist_submissions(created_at DESC);

COMMENT ON TABLE checklist_submissions IS 'Отправленные заполненные чеклисты: шеф и су-шеф получают во входящих. payload: { items: [{ title, done }], submittedByName, section }.';
