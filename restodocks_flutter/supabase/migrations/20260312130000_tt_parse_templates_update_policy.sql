-- UPDATE policy для upsert в tt_parse_templates (обучение шаблонами)
CREATE POLICY "authenticated_update_tt_parse_templates" ON tt_parse_templates
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
