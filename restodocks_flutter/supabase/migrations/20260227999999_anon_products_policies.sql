-- Restodocks НЕ использует Supabase Auth — все запросы идут с anon ключом.
-- Без этих политик продукты и номенклатура не сохраняются и не читаются.

-- products: anon может делать всё (SELECT, INSERT, UPDATE, DELETE)
DROP POLICY IF EXISTS "anon_select_products" ON products;
CREATE POLICY "anon_select_products" ON products
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_products" ON products;
CREATE POLICY "anon_insert_products" ON products
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_products" ON products;
CREATE POLICY "anon_update_products" ON products
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_products" ON products;
CREATE POLICY "anon_delete_products" ON products
  FOR DELETE TO anon USING (true);

-- establishment_products: anon может делать всё
DROP POLICY IF EXISTS "anon_select_establishment_products" ON establishment_products;
CREATE POLICY "anon_select_establishment_products" ON establishment_products
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_establishment_products" ON establishment_products;
CREATE POLICY "anon_insert_establishment_products" ON establishment_products
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_establishment_products" ON establishment_products;
CREATE POLICY "anon_update_establishment_products" ON establishment_products
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_establishment_products" ON establishment_products;
CREATE POLICY "anon_delete_establishment_products" ON establishment_products
  FOR DELETE TO anon USING (true);

-- product_price_history: anon может делать всё
DROP POLICY IF EXISTS "anon_select_product_price_history" ON product_price_history;
CREATE POLICY "anon_select_product_price_history" ON product_price_history
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_product_price_history" ON product_price_history;
CREATE POLICY "anon_insert_product_price_history" ON product_price_history
  FOR INSERT TO anon WITH CHECK (true);

-- tech_cards: anon может делать всё
DROP POLICY IF EXISTS "anon_select_tech_cards" ON tech_cards;
CREATE POLICY "anon_select_tech_cards" ON tech_cards
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_tech_cards" ON tech_cards;
CREATE POLICY "anon_insert_tech_cards" ON tech_cards
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_tech_cards" ON tech_cards;
CREATE POLICY "anon_update_tech_cards" ON tech_cards
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_tech_cards" ON tech_cards;
CREATE POLICY "anon_delete_tech_cards" ON tech_cards
  FOR DELETE TO anon USING (true);

-- tt_ingredients: anon может делать всё
DROP POLICY IF EXISTS "anon_select_tt_ingredients" ON tt_ingredients;
CREATE POLICY "anon_select_tt_ingredients" ON tt_ingredients
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_tt_ingredients" ON tt_ingredients;
CREATE POLICY "anon_insert_tt_ingredients" ON tt_ingredients
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_tt_ingredients" ON tt_ingredients;
CREATE POLICY "anon_update_tt_ingredients" ON tt_ingredients
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_tt_ingredients" ON tt_ingredients;
CREATE POLICY "anon_delete_tt_ingredients" ON tt_ingredients
  FOR DELETE TO anon USING (true);
