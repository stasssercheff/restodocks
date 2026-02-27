-- RLS политики для Storage bucket "avatars" (фото профилей сотрудников)
-- Исправляет: new row violates row-level security policy (403 Unauthorized)

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_insert_authenticated'
  ) THEN
    CREATE POLICY "avatars_insert_authenticated"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_update_authenticated'
  ) THEN
    CREATE POLICY "avatars_update_authenticated"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'avatars')
    WITH CHECK (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_select_public'
  ) THEN
    CREATE POLICY "avatars_select_public"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_delete_authenticated'
  ) THEN
    CREATE POLICY "avatars_delete_authenticated"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'avatars');
  END IF;
END $$;
