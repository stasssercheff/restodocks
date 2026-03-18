-- One-time "Getting started" dialog flag (per employee).
-- We store it server-side to avoid re-showing after web deploys / storage resets.

ALTER TABLE public.employees
ADD COLUMN IF NOT EXISTS getting_started_shown BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill for existing employees so the dialog does not appear for long-registered users.
UPDATE public.employees
SET getting_started_shown = TRUE
WHERE getting_started_shown = FALSE;

