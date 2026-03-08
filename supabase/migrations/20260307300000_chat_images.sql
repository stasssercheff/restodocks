-- Фото в чате между сотрудниками
ALTER TABLE employee_direct_messages
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Бакет для фото в чатах
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('chat_images', 'chat_images', true, 5242880)
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

DROP POLICY IF EXISTS "chat_images_insert_authenticated" ON storage.objects;
CREATE POLICY "chat_images_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat_images');

DROP POLICY IF EXISTS "chat_images_select_public" ON storage.objects;
CREATE POLICY "chat_images_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'chat_images');
