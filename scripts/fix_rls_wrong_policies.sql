-- Опционально: удаление политик с employees.id = auth.uid() (неправильный паттерн).
-- Выполнять только если эти политики есть (например, после final_rls_setup.sql).
-- Основная миграция 20260225170000 уже удалила order_documents_establishment_access.

DROP POLICY IF EXISTS "establishments_owner_access" ON establishments;
DROP POLICY IF EXISTS "employees_establishment_access" ON employees;
DROP POLICY IF EXISTS "tech_cards_establishment_access" ON tech_cards;
DROP POLICY IF EXISTS "checklists_establishment_access" ON checklists;
DROP POLICY IF EXISTS "establishment_products_access" ON establishment_products;
DROP POLICY IF EXISTS "tt_ingredients_tech_card_access" ON tt_ingredients;
DROP POLICY IF EXISTS "checklist_items_checklist_access" ON checklist_items;
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "password_reset_tokens_owner_access" ON password_reset_tokens;
DROP POLICY IF EXISTS "password_reset_tokens_owner_global" ON password_reset_tokens;
DROP POLICY IF EXISTS "schedules_establishment_access" ON schedules;
