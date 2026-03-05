-- Сообщения между сотрудниками одного заведения.
CREATE TABLE IF NOT EXISTS employee_direct_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CHECK (sender_employee_id != recipient_employee_id)
);

CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_sender ON employee_direct_messages(sender_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_recipient ON employee_direct_messages(recipient_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_created ON employee_direct_messages(created_at DESC);

ALTER TABLE employee_direct_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_employee_messages_select" ON employee_direct_messages
  FOR SELECT TO authenticated
  USING (sender_employee_id = auth.uid() OR recipient_employee_id = auth.uid());

CREATE POLICY "auth_employee_messages_insert" ON employee_direct_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_employee_id = auth.uid()
    AND recipient_employee_id != auth.uid()
    AND recipient_employee_id IN (
      SELECT id FROM employees e
      WHERE e.establishment_id = (SELECT establishment_id FROM employees WHERE id = auth.uid())
    )
  );

COMMENT ON TABLE employee_direct_messages IS 'Личные сообщения между сотрудниками заведения.';
