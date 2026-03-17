-- Part 2: policies (run after Part 1)
CREATE POLICY "auth_select_employee_birthday_change_notifications" ON employee_birthday_change_notifications
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees
      WHERE id = auth.uid()
        AND (roles @> ARRAY['owner'] OR roles @> ARRAY['executive_chef'] OR roles @> ARRAY['sous_chef']
             OR roles @> ARRAY['bar_manager'] OR roles @> ARRAY['floor_manager'] OR roles @> ARRAY['general_manager']
             OR department = 'management')
    )
  );

CREATE POLICY "auth_insert_employee_birthday_change_own" ON employee_birthday_change_notifications
  FOR INSERT TO authenticated
  WITH CHECK (
    employee_id = auth.uid()
    AND changed_by_employee_id = auth.uid()
    AND establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );
