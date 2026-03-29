-- Запуск в SQL Editor (Supabase) или psql: обзор RLS-политик для ручного аудита.
-- Ищите строки с roles = {anon} и qual = true — кандидаты на ужесточение.

SELECT
  schemaname,
  tablename,
  policyname,
  roles,
  cmd,
  qual::text AS using_expr,
  with_check::text AS with_check_expr
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
