-- После industry RLS у product_nutrition_links не осталось политик для anon.
-- Клиент иногда шлёт запросы до готовности JWT → роль anon; без SELECT-политики
-- PostgREST отдаёт 403. Политика USING (false): запрос допустим, строк не видно (безопасно).

DROP POLICY IF EXISTS "anon_select_product_nutrition_links_empty" ON public.product_nutrition_links;
CREATE POLICY "anon_select_product_nutrition_links_empty"
  ON public.product_nutrition_links
  FOR SELECT
  TO anon
  USING (false);
