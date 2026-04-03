-- Запуск в SQL Editor (Supabase): список SECURITY DEFINER функций в public для ручного ревью.
-- Смотрите: нет ли лишнего GRANT PUBLIC, совпадает ли search_path, есть ли проверка caller/tenant.

SELECT
  n.nspname AS schema,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS args,
  CASE WHEN p.prosecdef THEN 'yes' ELSE 'no' END AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
ORDER BY p.proname;
