-- Личные сообщения между сотрудниками одного заведения
CREATE TABLE IF NOT EXISTS employee_direct_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_sender ON employee_direct_messages(sender_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_recipient ON employee_direct_messages(recipient_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_created ON employee_direct_messages(created_at DESC);

COMMENT ON TABLE employee_direct_messages IS 'Личные сообщения между сотрудниками';

-- RLS: через anon key — доступ к сообщениям в рамках заведения
-- (при Auth: можно усилить проверкой auth_user_id)
ALTER TABLE employee_direct_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY employee_direct_messages_select
  ON employee_direct_messages FOR SELECT
  USING (true);

CREATE POLICY employee_direct_messages_insert
  ON employee_direct_messages FOR INSERT
  WITH CHECK (true);
