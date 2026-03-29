-- Paste-safe: no double-quoted policy names (avoids broken paste mid-"...").
-- nutrition_aliases
DROP POLICY IF EXISTS anon_select_nutrition_aliases ON public.nutrition_aliases;
DROP POLICY IF EXISTS anon_write_nutrition_aliases ON public.nutrition_aliases;
DROP POLICY IF EXISTS anon_update_nutrition_aliases ON public.nutrition_aliases;
DROP POLICY IF EXISTS auth_select_nutrition_aliases ON public.nutrition_aliases;
DROP POLICY IF EXISTS auth_write_nutrition_aliases ON public.nutrition_aliases;
DROP POLICY IF EXISTS auth_update_nutrition_aliases ON public.nutrition_aliases;

CREATE POLICY auth_select_nutrition_aliases ON public.nutrition_aliases
  FOR SELECT TO authenticated USING (true);

CREATE POLICY auth_write_nutrition_aliases ON public.nutrition_aliases
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY auth_update_nutrition_aliases ON public.nutrition_aliases
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- product_nutrition_links
DROP POLICY IF EXISTS anon_select_product_nutrition_links ON public.product_nutrition_links;
DROP POLICY IF EXISTS anon_write_product_nutrition_links ON public.product_nutrition_links;
DROP POLICY IF EXISTS anon_update_product_nutrition_links ON public.product_nutrition_links;
DROP POLICY IF EXISTS auth_select_product_nutrition_links ON public.product_nutrition_links;
DROP POLICY IF EXISTS auth_write_product_nutrition_links ON public.product_nutrition_links;
DROP POLICY IF EXISTS auth_update_product_nutrition_links ON public.product_nutrition_links;
DROP POLICY IF EXISTS auth_delete_product_nutrition_links ON public.product_nutrition_links;

CREATE POLICY auth_select_product_nutrition_links ON public.product_nutrition_links
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.establishment_products ep
      WHERE ep.product_id = product_nutrition_links.product_id
        AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

CREATE POLICY auth_write_product_nutrition_links ON public.product_nutrition_links
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.establishment_products ep
      WHERE ep.product_id = product_nutrition_links.product_id
        AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

CREATE POLICY auth_update_product_nutrition_links ON public.product_nutrition_links
  FOR UPDATE TO authenticated
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

CREATE POLICY auth_delete_product_nutrition_links ON public.product_nutrition_links
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.establishment_products ep
      WHERE ep.product_id = product_nutrition_links.product_id
        AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

-- nutrition_research_queue
DROP POLICY IF EXISTS anon_select_nutrition_research_queue ON public.nutrition_research_queue;
DROP POLICY IF EXISTS anon_write_nutrition_research_queue ON public.nutrition_research_queue;
DROP POLICY IF EXISTS anon_update_nutrition_research_queue ON public.nutrition_research_queue;
DROP POLICY IF EXISTS auth_select_nutrition_research_queue ON public.nutrition_research_queue;
DROP POLICY IF EXISTS auth_write_nutrition_research_queue ON public.nutrition_research_queue;
DROP POLICY IF EXISTS auth_update_nutrition_research_queue ON public.nutrition_research_queue;
DROP POLICY IF EXISTS auth_delete_nutrition_research_queue ON public.nutrition_research_queue;

CREATE POLICY auth_select_nutrition_research_queue ON public.nutrition_research_queue
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.establishment_products ep
      WHERE ep.product_id = nutrition_research_queue.product_id
        AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

CREATE POLICY auth_write_nutrition_research_queue ON public.nutrition_research_queue
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.establishment_products ep
      WHERE ep.product_id = nutrition_research_queue.product_id
        AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

CREATE POLICY auth_update_nutrition_research_queue ON public.nutrition_research_queue
  FOR UPDATE TO authenticated
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

CREATE POLICY auth_delete_nutrition_research_queue ON public.nutrition_research_queue
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.establishment_products ep
      WHERE ep.product_id = nutrition_research_queue.product_id
        AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );
