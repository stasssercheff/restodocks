-- Скрипт проверки таблиц ХАССП и RLS. Запустить в Supabase SQL Editor.

-- 1. Проверка существования таблиц
SELECT
  'haccp_numeric_logs' AS table_name,
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'haccp_numeric_logs') AS exists
UNION ALL
SELECT
  'haccp_status_logs',
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'haccp_status_logs')
UNION ALL
SELECT
  'haccp_quality_logs',
  EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'haccp_quality_logs');

-- 2. Проверка колонки establishment_id во всех таблицах
SELECT
  c.table_name,
  c.column_name,
  c.is_nullable,
  c.data_type
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN ('haccp_numeric_logs', 'haccp_status_logs', 'haccp_quality_logs')
  AND c.column_name = 'establishment_id'
ORDER BY c.table_name;

-- 3. Проверка RLS: включён ли и какие политики есть
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual AS using_expression,
  with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('haccp_numeric_logs', 'haccp_status_logs', 'haccp_quality_logs')
ORDER BY tablename, policyname;
