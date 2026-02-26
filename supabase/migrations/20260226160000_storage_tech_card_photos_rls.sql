-- RLS политики для Storage bucket "tech_card_photos" (фото ТТК — блюда и ПФ)
-- Позволяет аутентифицированным пользователям загружать и удалять фото

-- INSERT: аутентифицированные пользователи могут загружать
CREATE POLICY "tech_card_photos_insert_authenticated"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'tech_card_photos');

-- UPDATE: нужен для upsert (uploadBinary с upsert: true)
CREATE POLICY "tech_card_photos_update_authenticated"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'tech_card_photos')
WITH CHECK (bucket_id = 'tech_card_photos');

-- SELECT: публичное чтение (bucket public)
CREATE POLICY "tech_card_photos_select_public"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'tech_card_photos');

-- DELETE: аутентифицированные могут удалять
CREATE POLICY "tech_card_photos_delete_authenticated"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'tech_card_photos');
