-- RLS политики для Storage bucket "tech_card_photos" (фото ТТК — блюда и ПФ)

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_insert_authenticated'
  ) THEN
    CREATE POLICY "tech_card_photos_insert_authenticated"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'tech_card_photos');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_update_authenticated'
  ) THEN
    CREATE POLICY "tech_card_photos_update_authenticated"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'tech_card_photos')
    WITH CHECK (bucket_id = 'tech_card_photos');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_select_public'
  ) THEN
    CREATE POLICY "tech_card_photos_select_public"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'tech_card_photos');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_delete_authenticated'
  ) THEN
    CREATE POLICY "tech_card_photos_delete_authenticated"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'tech_card_photos');
  END IF;
END $$;
