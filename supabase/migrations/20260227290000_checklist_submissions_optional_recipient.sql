-- Делаем recipient_chef_id необязательным: чеклисты сохраняются для заведения без обязательного получателя.
ALTER TABLE checklist_submissions ALTER COLUMN recipient_chef_id DROP NOT NULL;

-- Обновляем RLS: доступ по establishment_id или как получатель
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_access" ON checklist_submissions;

CREATE POLICY "checklist_submissions_access" ON checklist_submissions
FOR ALL USING (
  recipient_chef_id = auth.uid()
  OR submitted_by_employee_id = auth.uid()
  OR establishment_id IN (
    SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid()
    UNION
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);
