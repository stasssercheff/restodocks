-- Auth-политики для tech_cards и tt_ingredients (Phase 1: authenticated после signIn)
-- Доступ по establishment_id: владелец или сотрудник заведения.
-- Поддерживаем auth_user_id и id (legacy owners: employees.id = auth.uid()).

-- Заведения пользователя: где он владелец или сотрудник
-- (auth_user_id для legacy→auth и новых; id для старых владельцев без auth_user_id)
CREATE OR REPLACE FUNCTION _auth_user_establishment_ids()
RETURNS SETOF UUID AS $$
  SELECT id FROM establishments
  WHERE owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid() OR id = auth.uid())
  UNION
  SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid() OR id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- tech_cards: SELECT, INSERT, UPDATE, DELETE для authenticated по establishment_id
DROP POLICY IF EXISTS "auth_select_tech_cards" ON tech_cards;
CREATE POLICY "auth_select_tech_cards" ON tech_cards
  FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT _auth_user_establishment_ids()));

DROP POLICY IF EXISTS "auth_insert_tech_cards" ON tech_cards;
CREATE POLICY "auth_insert_tech_cards" ON tech_cards
  FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT _auth_user_establishment_ids()));

DROP POLICY IF EXISTS "auth_update_tech_cards" ON tech_cards;
CREATE POLICY "auth_update_tech_cards" ON tech_cards
  FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT _auth_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT _auth_user_establishment_ids()));

DROP POLICY IF EXISTS "auth_delete_tech_cards" ON tech_cards;
CREATE POLICY "auth_delete_tech_cards" ON tech_cards
  FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT _auth_user_establishment_ids()));

-- tt_ingredients: через tech_cards (доступные ТТК)
DROP POLICY IF EXISTS "auth_select_tt_ingredients" ON tt_ingredients;
CREATE POLICY "auth_select_tt_ingredients" ON tt_ingredients
  FOR SELECT TO authenticated
  USING (tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id IN (SELECT _auth_user_establishment_ids())));

DROP POLICY IF EXISTS "auth_insert_tt_ingredients" ON tt_ingredients;
CREATE POLICY "auth_insert_tt_ingredients" ON tt_ingredients
  FOR INSERT TO authenticated
  WITH CHECK (tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id IN (SELECT _auth_user_establishment_ids())));

DROP POLICY IF EXISTS "auth_update_tt_ingredients" ON tt_ingredients;
CREATE POLICY "auth_update_tt_ingredients" ON tt_ingredients
  FOR UPDATE TO authenticated
  USING (tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id IN (SELECT _auth_user_establishment_ids())))
  WITH CHECK (tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id IN (SELECT _auth_user_establishment_ids())));

DROP POLICY IF EXISTS "auth_delete_tt_ingredients" ON tt_ingredients;
CREATE POLICY "auth_delete_tt_ingredients" ON tt_ingredients
  FOR DELETE TO authenticated
  USING (tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id IN (SELECT _auth_user_establishment_ids())));
