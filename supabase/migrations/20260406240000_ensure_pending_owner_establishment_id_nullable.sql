-- Owner-first: pending_owner_registrations.establishment_id может быть NULL до создания первого заведения.
-- Если миграция 20260406200000 не применялась, INSERT с NULL даёт 23502.

ALTER TABLE public.pending_owner_registrations
  ALTER COLUMN establishment_id DROP NOT NULL;

COMMENT ON COLUMN public.pending_owner_registrations.establishment_id IS
  'NULL — регистрация владельца до первого заведения (owner-first).';
