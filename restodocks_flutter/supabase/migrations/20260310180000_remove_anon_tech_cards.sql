-- Phase 2: Снятие anon для tech_cards и tt_ingredients.
-- Доступ только через auth (JWT). Legacy без auth_user_id — повторный вход для получения JWT.

DROP POLICY IF EXISTS "anon_select_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "anon_insert_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "anon_update_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "anon_delete_tech_cards" ON tech_cards;

DROP POLICY IF EXISTS "anon_select_tt_ingredients" ON tt_ingredients;
DROP POLICY IF EXISTS "anon_insert_tt_ingredients" ON tt_ingredients;
DROP POLICY IF EXISTS "anon_update_tt_ingredients" ON tt_ingredients;
DROP POLICY IF EXISTS "anon_delete_tt_ingredients" ON tt_ingredients;
