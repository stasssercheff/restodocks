-- RLS политики для Storage bucket "avatars" (фото профилей сотрудников)
-- Исправляет: new row violates row-level security policy (403 Unauthorized)

-- INSERT: аутентифицированные пользователи могут загружать в avatars
CREATE POLICY "avatars_insert_authenticated"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars');

-- UPDATE: нужен для upsert (uploadBinary с upsert: true)
CREATE POLICY "avatars_update_authenticated"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars')
WITH CHECK (bucket_id = 'avatars');

-- SELECT: публичное чтение (bucket public)
CREATE POLICY "avatars_select_public"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'avatars');

-- DELETE: аутентифицированные могут удалять (для замены фото)
CREATE POLICY "avatars_delete_authenticated"
ON storage.objects
FOR DELETE
TO authenticated
USING (bucket_id = 'avatars');
