-- Групповые чаты между сотрудниками заведения.

CREATE TABLE IF NOT EXISTS chat_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_establishment ON chat_rooms(establishment_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_created ON chat_rooms(created_at DESC);

COMMENT ON TABLE chat_rooms IS 'Групповые чаты заведения. name — переименовываемое название.';

CREATE TABLE IF NOT EXISTS chat_room_members (
  chat_room_id UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (chat_room_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_room_members_employee ON chat_room_members(employee_id);

CREATE TABLE IF NOT EXISTS chat_room_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_room_id UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  content TEXT NOT NULL DEFAULT '',
  image_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_room_messages_room ON chat_room_messages(chat_room_id);
CREATE INDEX IF NOT EXISTS idx_chat_room_messages_created ON chat_room_messages(created_at DESC);

COMMENT ON TABLE chat_room_messages IS 'Сообщения в групповом чате.';

-- RLS
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_room_messages ENABLE ROW LEVEL SECURITY;

-- Читать комнаты: только участники (через chat_room_members).
CREATE POLICY chat_rooms_select ON chat_rooms FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  );

-- Создавать комнаты: сотрудник своего заведения.
CREATE POLICY chat_rooms_insert ON chat_rooms FOR INSERT TO authenticated
  WITH CHECK (
    created_by_employee_id = auth.uid()
    AND establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- Обновлять (переименование): только участник комнаты.
CREATE POLICY chat_rooms_update ON chat_rooms FOR UPDATE TO authenticated
  USING (
    id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  )
  WITH CHECK (true);

-- Удалять комнаты: только создатель (опционально; можно не давать).
-- Пока не добавляем DELETE policy — удаление только через каскад при удалении заведения.

-- Участники: читать/добавлять/удалять только свои записи или в комнатах, где состоишь.
CREATE POLICY chat_room_members_select ON chat_room_members FOR SELECT TO authenticated
  USING (
    chat_room_id IN (
      SELECT id FROM chat_rooms WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

-- Вставка: добавлять себя в комнату или создатель комнаты добавляет других участников.
CREATE POLICY chat_room_members_insert ON chat_room_members FOR INSERT TO authenticated
  WITH CHECK (
    employee_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM chat_rooms cr
      WHERE cr.id = chat_room_members.chat_room_id AND cr.created_by_employee_id = auth.uid()
    )
  );

CREATE POLICY chat_room_members_delete ON chat_room_members FOR DELETE TO authenticated
  USING (employee_id = auth.uid());

-- Сообщения: читать только в комнатах, где участник; писать — только участник.
CREATE POLICY chat_room_messages_select ON chat_room_messages FOR SELECT TO authenticated
  USING (
    chat_room_id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  );

CREATE POLICY chat_room_messages_insert ON chat_room_messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_employee_id = auth.uid()
    AND chat_room_id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  );

GRANT SELECT, INSERT, UPDATE ON chat_rooms TO authenticated;
GRANT SELECT, INSERT, DELETE ON chat_room_members TO authenticated;
GRANT SELECT, INSERT ON chat_room_messages TO authenticated;

-- Realtime для групповых сообщений
ALTER PUBLICATION supabase_realtime ADD TABLE chat_room_messages;
