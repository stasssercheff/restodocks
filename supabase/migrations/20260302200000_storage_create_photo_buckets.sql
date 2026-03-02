-- Создание публичных бакетов для фото профиля и ТТК
-- avatars      — фото профилей сотрудников
-- tech_card_photos — фото блюд и полуфабрикатов в ТТК

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('avatars',           'avatars',           true, 5242880),   -- 5 MB
  ('tech_card_photos',  'tech_card_photos',  true, 10485760)   -- 10 MB
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

-- RLS для avatars
DROP POLICY IF EXISTS "avatars_insert_authenticated" ON storage.objects;
CREATE POLICY "avatars_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_update_authenticated" ON storage.objects;
CREATE POLICY "avatars_update_authenticated"
  ON storage.objects FOR UPDATE TO authenticated
  USING  (bucket_id = 'avatars')
  WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_select_public" ON storage.objects;
CREATE POLICY "avatars_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_delete_authenticated" ON storage.objects;
CREATE POLICY "avatars_delete_authenticated"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars');

-- RLS для tech_card_photos
DROP POLICY IF EXISTS "tech_card_photos_insert_authenticated" ON storage.objects;
CREATE POLICY "tech_card_photos_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'tech_card_photos');

DROP POLICY IF EXISTS "tech_card_photos_update_authenticated" ON storage.objects;
CREATE POLICY "tech_card_photos_update_authenticated"
  ON storage.objects FOR UPDATE TO authenticated
  USING  (bucket_id = 'tech_card_photos')
  WITH CHECK (bucket_id = 'tech_card_photos');

DROP POLICY IF EXISTS "tech_card_photos_select_public" ON storage.objects;
CREATE POLICY "tech_card_photos_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'tech_card_photos');

DROP POLICY IF EXISTS "tech_card_photos_delete_authenticated" ON storage.objects;
CREATE POLICY "tech_card_photos_delete_authenticated"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'tech_card_photos');
