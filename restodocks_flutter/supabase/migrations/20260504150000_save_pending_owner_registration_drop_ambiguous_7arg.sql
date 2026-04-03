-- PostgREST PGRST203: "Could not choose the best candidate function" when two
-- overloads of save_pending_owner_registration exist. Migration 20260502190000
-- added an 8-arg variant with p_position_role; CREATE OR REPLACE does not
-- remove the older 7-arg signature, so both remained.
--
-- Drop the legacy 7-parameter overload. The remaining function has DEFAULTs for
-- p_roles, p_preferred_language, and p_position_role (see 20260502190000).

DROP FUNCTION IF EXISTS public.save_pending_owner_registration(
  uuid,
  uuid,
  text,
  text,
  text,
  text[],
  text
);
