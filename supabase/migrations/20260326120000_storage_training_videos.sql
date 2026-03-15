-- Бакет для обучающих видео (приватный — доступ только по signed URL из Edge Function).
-- Для российских IP — видео из Supabase; для остальных — YouTube.
-- Загрузка: через Dashboard или авторизованный скрипт.

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('training_videos', 'training_videos', false, 104857600)
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

-- Только service_role создаёт signed URL. Для загрузки — authenticated (владельцы через Dashboard).
DROP POLICY IF EXISTS "training_videos_insert_authenticated" ON storage.objects;
CREATE POLICY "training_videos_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'training_videos');

-- Чтение — только через signed URL (Edge Function), public SELECT не даём.
-- service_role обходит RLS при createSignedUrl.
