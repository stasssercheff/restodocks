-- Verify public.create_co_owner_from_invitation includes p_birthday (migration 20260504140000).
-- Run in Supabase Dashboard → SQL Editor against your single project.
--
-- EXPECTED after migration:
--   identity_args contains: p_invitation_token text, p_full_name text, p_surname text, p_birthday date
--   function body contains: p_birthday and INSERT ... birthday ...
--
-- If you only see three arguments (no p_birthday), apply:
--   supabase/migrations/20260504140000_co_owner_from_invitation_birthday.sql
-- (same file under restodocks_flutter/supabase/migrations/)

-- 1) Argument list (quick check)
SELECT pg_get_function_identity_arguments(p.oid) AS identity_args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'create_co_owner_from_invitation';

-- 2) Full definition (confirm p_birthday and employees.birthday in INSERT)
SELECT pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'create_co_owner_from_invitation';
