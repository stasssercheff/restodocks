-- 23514: preferred_language = kk (и др.) ломали старый CHECK без kk/de/fr.
-- Список = LocalizationService.supportedLocales: ru, en, es, kk, de, fr, it, tr, vi.

ALTER TABLE public.employees
  DROP CONSTRAINT IF EXISTS employees_preferred_language_check;

ALTER TABLE public.employees
  ADD CONSTRAINT employees_preferred_language_check
  CHECK (
    preferred_language IS NULL
    OR preferred_language = ANY (
      ARRAY['ru', 'en', 'es', 'kk', 'de', 'fr', 'it', 'tr', 'vi']::text[]
    )
  );
