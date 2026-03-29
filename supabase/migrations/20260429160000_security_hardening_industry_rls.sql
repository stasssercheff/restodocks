-- =============================================================================
-- Industry-style RLS hardening (Phase 2): remove remaining anon broad access where
-- the app uses Supabase Auth; scope rows by tenant where applicable.
-- Does NOT touch: registration RPCs, pending_owner_registration anon INSERT,
-- platform_config, co_owner anon flows, find_establishment_by_pin, etc.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) product_aliases: remove anon SELECT; explicit auth SELECT by establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_product_aliases" ON public.product_aliases;
DROP POLICY IF EXISTS "auth_select_product_aliases" ON public.product_aliases;

CREATE POLICY "auth_select_product_aliases"
ON public.product_aliases
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

-- ---------------------------------------------------------------------------
-- 2) product_alias_rejections: idempotent final policies (stricter than early P0)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "anon_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_update_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_delete_product_alias_rejections" ON public.product_alias_rejections;

CREATE POLICY "auth_select_product_alias_rejections"
ON public.product_alias_rejections
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_insert_product_alias_rejections"
ON public.product_alias_rejections
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_update_product_alias_rejections"
ON public.product_alias_rejections
FOR UPDATE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
)
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_delete_product_alias_rejections"
ON public.product_alias_rejections
FOR DELETE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

-- ---------------------------------------------------------------------------
-- 3) ai_ttk_daily_usage: Edge Functions use service_role (bypass RLS). Remove anon SELECT.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_ai_ttk_usage" ON public.ai_ttk_daily_usage;

DROP POLICY IF EXISTS "auth_select_ai_ttk_usage" ON public.ai_ttk_daily_usage;
CREATE POLICY "auth_select_ai_ttk_usage"
ON public.ai_ttk_daily_usage
FOR SELECT
TO authenticated
USING (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 4) iiko_blank_versions: authenticated + tenant only (Flutter uses Auth session)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_iiko_blank_versions_select" ON public.iiko_blank_versions;
DROP POLICY IF EXISTS "anon_iiko_blank_versions_insert" ON public.iiko_blank_versions;

DROP POLICY IF EXISTS "auth_iiko_blank_versions_select" ON public.iiko_blank_versions;
DROP POLICY IF EXISTS "auth_iiko_blank_versions_insert" ON public.iiko_blank_versions;
DROP POLICY IF EXISTS "auth_iiko_blank_versions_delete" ON public.iiko_blank_versions;

CREATE POLICY "auth_iiko_blank_versions_select"
ON public.iiko_blank_versions
FOR SELECT
TO authenticated
USING (establishment_id IN (SELECT public.current_user_establishment_ids()));

CREATE POLICY "auth_iiko_blank_versions_insert"
ON public.iiko_blank_versions
FOR INSERT
TO authenticated
WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

CREATE POLICY "auth_iiko_blank_versions_delete"
ON public.iiko_blank_versions
FOR DELETE
TO authenticated
USING (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 5) tt_parse_corrections: no anon; scope by establishment (NULL treated as global read for signed-in users)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_tt_parse_corrections" ON public.tt_parse_corrections;
DROP POLICY IF EXISTS "anon_insert_tt_parse_corrections" ON public.tt_parse_corrections;

DROP POLICY IF EXISTS "authenticated_select_tt_parse_corrections" ON public.tt_parse_corrections;
DROP POLICY IF EXISTS "authenticated_insert_tt_parse_corrections" ON public.tt_parse_corrections;

CREATE POLICY "authenticated_select_tt_parse_corrections"
ON public.tt_parse_corrections
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "authenticated_insert_tt_parse_corrections"
ON public.tt_parse_corrections
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

-- ---------------------------------------------------------------------------
-- 6) Nutrition layer: remove anon; keep global reads/writes for authenticated only.
--    Links/queue scoped via establishment_products (products has no establishment_id).
-- ---------------------------------------------------------------------------
-- nutrition_profiles
DROP POLICY IF EXISTS "anon_select_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "anon_write_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "anon_update_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_select_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_write_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_update_nutrition_profiles" ON public.nutrition_profiles;

CREATE POLICY "auth_select_nutrition_profiles"
ON public.nutrition_profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth_write_nutrition_profiles"
ON public.nutrition_profiles FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "auth_update_nutrition_profiles"
ON public.nutrition_profiles FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- nutrition_aliases
DROP POLICY IF EXISTS "anon_select_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "anon_write_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "anon_update_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_select_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_write_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_update_nutrition_aliases" ON public.nutrition_aliases;

CREATE POLICY "auth_select_nutrition_aliases"
ON public.nutrition_aliases FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth_write_nutrition_aliases"
ON public.nutrition_aliases FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "auth_update_nutrition_aliases"
ON public.nutrition_aliases FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- product_nutrition_links
DROP POLICY IF EXISTS "anon_select_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "anon_write_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "anon_update_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_select_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_write_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_update_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_delete_product_nutrition_links" ON public.product_nutrition_links;

CREATE POLICY "auth_select_product_nutrition_links"
ON public.product_nutrition_links
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_write_product_nutrition_links"
ON public.product_nutrition_links
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_update_product_nutrition_links"
ON public.product_nutrition_links
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_delete_product_nutrition_links"
ON public.product_nutrition_links
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

-- nutrition_research_queue
DROP POLICY IF EXISTS "anon_select_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "anon_write_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "anon_update_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_select_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_write_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_update_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_delete_nutrition_research_queue" ON public.nutrition_research_queue;

CREATE POLICY "auth_select_nutrition_research_queue"
ON public.nutrition_research_queue
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_write_nutrition_research_queue"
ON public.nutrition_research_queue
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_update_nutrition_research_queue"
ON public.nutrition_research_queue
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_delete_nutrition_research_queue"
ON public.nutrition_research_queue
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);
