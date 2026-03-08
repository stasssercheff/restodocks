-- Добавляем read_at для непрочитанных сообщений и включаем Realtime.
ALTER TABLE employee_direct_messages
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMP WITH TIME ZONE;

DROP POLICY IF EXISTS "auth_employee_messages_update_read" ON employee_direct_messages;
CREATE POLICY "auth_employee_messages_update_read" ON employee_direct_messages
  FOR UPDATE TO authenticated
  USING (recipient_employee_id = auth.uid())
  WITH CHECK (recipient_employee_id = auth.uid());

-- Включаем Realtime для employee_direct_messages (если ещё не добавлена)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE employee_direct_messages;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
