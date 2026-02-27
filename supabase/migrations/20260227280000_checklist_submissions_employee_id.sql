-- checklist_submissions: добавить submitted_by_employee_id и recipient_chef_id если нет
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS submitted_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS recipient_chef_id UUID REFERENCES employees(id) ON DELETE SET NULL;
