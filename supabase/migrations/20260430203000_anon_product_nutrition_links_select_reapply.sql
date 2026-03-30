-- Повторное применение: на части прод-окружений миграция 20260430191000 не накатывалась,
-- из-за чего у anon не остаётся ни одной SELECT-политики и PostgREST отдаёт 403 на любом SELECT.

DROP POLICY IF EXISTS "anon_select_product_nutrition_links_empty" ON public.product_nutrition_links;
CREATE POLICY "anon_select_product_nutrition_links_empty"
  ON public.product_nutrition_links
  FOR SELECT
  TO anon
  USING (false);
