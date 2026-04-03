-- Запуск в SQL Editor (Supabase) или psql: обзор RLS-политик для ручного аудита.
-- Ищите строки с roles = {anon} и qual = true — кандидаты на ужесточение.
-- Список SECURITY DEFINER: см. scripts/security_audit_definer_functions.sql

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

-- Кандидаты: anon и выражение USING = true (широкий доступ)
SELECT tablename, policyname, cmd, qual::text AS using_expr
FROM pg_policies
WHERE schemaname = 'public'
  AND 'anon' = ANY (roles)
  AND qual IS NOT NULL
  AND trim(qual::text) = 'true'
ORDER BY tablename, policyname;

-- Кандидаты: роль public на таблице employees / establishment_products (если остались ручные политики)
SELECT tablename, policyname, roles, cmd, qual::text AS using_expr
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('employees', 'establishment_products')
ORDER BY tablename, policyname;
