-- Голосовые сообщения в личном чате сотрудников
ALTER TABLE employee_direct_messages
  ADD COLUMN IF NOT EXISTS audio_url TEXT,
  ADD COLUMN IF NOT EXISTS audio_duration_seconds INTEGER;

COMMENT ON COLUMN employee_direct_messages.audio_url IS 'Публичный URL аудио в Storage (m4a/aac)';
COMMENT ON COLUMN employee_direct_messages.audio_duration_seconds IS 'Длительность записи в секундах';

-- Бакет для голосовых вложений
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('chat_voice', 'chat_voice', true, 3145728)
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

DROP POLICY IF EXISTS "chat_voice_insert_authenticated" ON storage.objects;
CREATE POLICY "chat_voice_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat_voice');

DROP POLICY IF EXISTS "chat_voice_select_public" ON storage.objects;
CREATE POLICY "chat_voice_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'chat_voice');
