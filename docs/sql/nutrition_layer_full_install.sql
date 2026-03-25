-- Полная установка слоя nutrition (таблицы + RLS).
-- Выполнить в Supabase → SQL → New query → вставить весь файл → Run.
-- Нужна существующая таблица public.products (как в Restodocks).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.nutrition_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_name text NOT NULL,
  canonical_name_ru text,
  canonical_name_en text,
  canonical_key text NOT NULL UNIQUE,
  category text,
  calories real,
  protein real,
  fat real,
  carbs real,
  contains_gluten boolean,
  contains_lactose boolean,
  source text,
  source_ref text,
  confidence real,
  status text DEFAULT 'external_unverified',
  last_verified_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nutrition_profiles_status ON public.nutrition_profiles(status);

CREATE TABLE IF NOT EXISTS public.nutrition_aliases (
  normalized_input text PRIMARY KEY,
  nutrition_profile_id uuid NOT NULL REFERENCES public.nutrition_profiles(id) ON DELETE CASCADE,
  raw_examples jsonb,
  confidence real,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nutrition_aliases_profile_id ON public.nutrition_aliases(nutrition_profile_id);

CREATE TABLE IF NOT EXISTS public.product_nutrition_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  nutrition_profile_id uuid NOT NULL REFERENCES public.nutrition_profiles(id) ON DELETE CASCADE,
  match_type text NOT NULL DEFAULT 'unmatched',
  match_confidence real,
  match_source text,
  normalized_query text,
  input_name_snapshot text,
  approved_by_user boolean NOT NULL DEFAULT false,
  approved_at timestamptz,
  last_checked_at timestamptz,
  recheck_after timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT product_nutrition_links_product_id_unique UNIQUE (product_id)
);

CREATE INDEX IF NOT EXISTS idx_product_nutrition_links_profile_id ON public.product_nutrition_links(nutrition_profile_id);
CREATE INDEX IF NOT EXISTS idx_product_nutrition_links_recheck ON public.product_nutrition_links(recheck_after);

CREATE TABLE IF NOT EXISTS public.nutrition_research_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  reason text NOT NULL,
  priority int NOT NULL DEFAULT 0,
  attempts int NOT NULL DEFAULT 0,
  max_attempts int NOT NULL DEFAULT 6,
  status text NOT NULL DEFAULT 'pending',
  next_retry_at timestamptz NOT NULL DEFAULT now(),
  locked_at timestamptz,
  worker_id text,
  last_error text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT nutrition_research_queue_product_reason_unique UNIQUE (product_id, reason)
);

CREATE INDEX IF NOT EXISTS idx_nutrition_research_queue_pending ON public.nutrition_research_queue(status, next_retry_at);
CREATE INDEX IF NOT EXISTS idx_nutrition_research_queue_product ON public.nutrition_research_queue(product_id);

ALTER TABLE public.nutrition_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_nutrition_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_research_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS anon_select_nutrition_profiles ON public.nutrition_profiles;
CREATE POLICY anon_select_nutrition_profiles ON public.nutrition_profiles FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS auth_select_nutrition_profiles ON public.nutrition_profiles;
CREATE POLICY auth_select_nutrition_profiles ON public.nutrition_profiles FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS anon_write_nutrition_profiles ON public.nutrition_profiles;
CREATE POLICY anon_write_nutrition_profiles ON public.nutrition_profiles FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS anon_update_nutrition_profiles ON public.nutrition_profiles;
CREATE POLICY anon_update_nutrition_profiles ON public.nutrition_profiles FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS auth_write_nutrition_profiles ON public.nutrition_profiles;
CREATE POLICY auth_write_nutrition_profiles ON public.nutrition_profiles FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS auth_update_nutrition_profiles ON public.nutrition_profiles;
CREATE POLICY auth_update_nutrition_profiles ON public.nutrition_profiles FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS anon_select_nutrition_aliases ON public.nutrition_aliases;
CREATE POLICY anon_select_nutrition_aliases ON public.nutrition_aliases FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS auth_select_nutrition_aliases ON public.nutrition_aliases;
CREATE POLICY auth_select_nutrition_aliases ON public.nutrition_aliases FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS anon_write_nutrition_aliases ON public.nutrition_aliases;
CREATE POLICY anon_write_nutrition_aliases ON public.nutrition_aliases FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS anon_update_nutrition_aliases ON public.nutrition_aliases;
CREATE POLICY anon_update_nutrition_aliases ON public.nutrition_aliases FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS auth_write_nutrition_aliases ON public.nutrition_aliases;
CREATE POLICY auth_write_nutrition_aliases ON public.nutrition_aliases FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS auth_update_nutrition_aliases ON public.nutrition_aliases;
CREATE POLICY auth_update_nutrition_aliases ON public.nutrition_aliases FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS anon_select_product_nutrition_links ON public.product_nutrition_links;
CREATE POLICY anon_select_product_nutrition_links ON public.product_nutrition_links FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS auth_select_product_nutrition_links ON public.product_nutrition_links;
CREATE POLICY auth_select_product_nutrition_links ON public.product_nutrition_links FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS anon_write_product_nutrition_links ON public.product_nutrition_links;
CREATE POLICY anon_write_product_nutrition_links ON public.product_nutrition_links FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS anon_update_product_nutrition_links ON public.product_nutrition_links;
CREATE POLICY anon_update_product_nutrition_links ON public.product_nutrition_links FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS auth_write_product_nutrition_links ON public.product_nutrition_links;
CREATE POLICY auth_write_product_nutrition_links ON public.product_nutrition_links FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS auth_update_product_nutrition_links ON public.product_nutrition_links;
CREATE POLICY auth_update_product_nutrition_links ON public.product_nutrition_links FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS anon_select_nutrition_research_queue ON public.nutrition_research_queue;
CREATE POLICY anon_select_nutrition_research_queue ON public.nutrition_research_queue FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS auth_select_nutrition_research_queue ON public.nutrition_research_queue;
CREATE POLICY auth_select_nutrition_research_queue ON public.nutrition_research_queue FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS anon_write_nutrition_research_queue ON public.nutrition_research_queue;
CREATE POLICY anon_write_nutrition_research_queue ON public.nutrition_research_queue FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS anon_update_nutrition_research_queue ON public.nutrition_research_queue;
CREATE POLICY anon_update_nutrition_research_queue ON public.nutrition_research_queue FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS auth_write_nutrition_research_queue ON public.nutrition_research_queue;
CREATE POLICY auth_write_nutrition_research_queue ON public.nutrition_research_queue FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS auth_update_nutrition_research_queue ON public.nutrition_research_queue;
CREATE POLICY auth_update_nutrition_research_queue ON public.nutrition_research_queue FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
