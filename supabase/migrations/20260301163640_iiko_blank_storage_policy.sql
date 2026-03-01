-- RLS политики для bucket "iiko-blanks" в Supabase Storage
-- Каждый аутентифицированный пользователь может читать/писать файлы
-- только своего заведения (путь: {establishment_id}/blank.xlsx)

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('iiko-blanks', 'iiko-blanks', false, 10485760)
ON CONFLICT (id) DO NOTHING;

-- SELECT (download)
DROP POLICY IF EXISTS "iiko_blanks_select" ON storage.objects;
CREATE POLICY "iiko_blanks_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );

-- INSERT (upload)
DROP POLICY IF EXISTS "iiko_blanks_insert" ON storage.objects;
CREATE POLICY "iiko_blanks_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );

-- UPDATE (overwrite)
DROP POLICY IF EXISTS "iiko_blanks_update" ON storage.objects;
CREATE POLICY "iiko_blanks_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );

-- DELETE
DROP POLICY IF EXISTS "iiko_blanks_delete" ON storage.objects;
CREATE POLICY "iiko_blanks_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );
