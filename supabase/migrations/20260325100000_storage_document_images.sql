-- Бакет для изображений в документах заведения

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('document_images', 'document_images', true, 5242880)
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

DROP POLICY IF EXISTS "document_images_insert_authenticated" ON storage.objects;
CREATE POLICY "document_images_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'document_images');

DROP POLICY IF EXISTS "document_images_select_public" ON storage.objects;
CREATE POLICY "document_images_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'document_images');

DROP POLICY IF EXISTS "document_images_delete_authenticated" ON storage.objects;
CREATE POLICY "document_images_delete_authenticated"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'document_images');
