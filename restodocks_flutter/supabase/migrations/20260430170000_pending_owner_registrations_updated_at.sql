-- save_pending_owner_registration (20260324203000) INSERT ... created_at, updated_at,
-- но в 20260309300000 таблица создана только с created_at — без updated_at.
ALTER TABLE public.pending_owner_registrations
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

UPDATE public.pending_owner_registrations
SET updated_at = created_at
WHERE updated_at IS NULL;

ALTER TABLE public.pending_owner_registrations
  ALTER COLUMN updated_at SET DEFAULT now();

ALTER TABLE public.pending_owner_registrations
  ALTER COLUMN updated_at SET NOT NULL;

COMMENT ON COLUMN public.pending_owner_registrations.updated_at IS
  'Обновляется при UPSERT в save_pending_owner_registration.';
