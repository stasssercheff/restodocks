-- ИСПРАВЛЕННЫЕ ПОЛИТИКИ RLS (ТОЛЬКО ДЛЯ ТАБЛИЦ С establishment_id)

-- ВКЛЮЧАЕМ RLS НА ВСЕХ ТАБЛИЦАХ
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE cooking_processes ENABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_reset_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- ПОЛИТИКИ ТОЛЬКО ДЛЯ ТАБЛИЦ С establishment_id
-- =============================================================================

-- Establishments: владелец видит своё заведение
DROP POLICY IF EXISTS "establishments_owner_access" ON establishments;
CREATE POLICY "establishments_owner_access" ON establishments
FOR ALL USING (id IN (
  SELECT establishment_id FROM employees
  WHERE id = auth.uid() AND 'owner' = ANY(roles)
));

-- Employees: сотрудники видят коллег из своего заведения
DROP POLICY IF EXISTS "employees_establishment_access" ON employees;
CREATE POLICY "employees_establishment_access" ON employees
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Tech cards: ТТК конкретного заведения
DROP POLICY IF EXISTS "tech_cards_establishment_access" ON tech_cards;
CREATE POLICY "tech_cards_establishment_access" ON tech_cards
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Checklists: чеклисты конкретного заведения
DROP POLICY IF EXISTS "checklists_establishment_access" ON checklists;
CREATE POLICY "checklists_establishment_access" ON checklists
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Order documents: документы заказов конкретного заведения
DROP POLICY IF EXISTS "order_documents_establishment_access" ON order_documents;
CREATE POLICY "order_documents_establishment_access" ON order_documents
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Establishment products: продукты конкретного заведения
DROP POLICY IF EXISTS "establishment_products_access" ON establishment_products;
CREATE POLICY "establishment_products_access" ON establishment_products
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Checklist submissions: отправленные чеклисты (шеф видит отправленные ему)
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
CREATE POLICY "checklist_submissions_recipient_access" ON checklist_submissions
FOR ALL USING (recipient_chef_id = auth.uid());

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ СВЯЗАННЫХ ТАБЛИЦ (через foreign keys)
-- =============================================================================

-- TT ingredients: доступ через tech_card_id
DROP POLICY IF EXISTS "tt_ingredients_tech_card_access" ON tt_ingredients;
CREATE POLICY "tt_ingredients_tech_card_access" ON tt_ingredients
FOR ALL USING (tech_card_id IN (
  SELECT id FROM tech_cards WHERE establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
));

-- Checklist items: доступ через checklist_id
DROP POLICY IF EXISTS "checklist_items_checklist_access" ON checklist_items;
CREATE POLICY "checklist_items_checklist_access" ON checklist_items
FOR ALL USING (checklist_id IN (
  SELECT id FROM checklists WHERE establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
));

-- =============================================================================
-- ГЛОБАЛЬНЫЕ ПОЛИТИКИ ДЛЯ ТАБЛИЦ БЕЗ establishment_id
-- =============================================================================

-- Все авторизованные пользователи видят глобальные данные
DROP POLICY IF EXISTS "products_access" ON products;
CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "cooking_processes_access" ON cooking_processes;
CREATE POLICY "cooking_processes_access" ON cooking_processes
FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "roles_access" ON roles;
CREATE POLICY "roles_access" ON roles
FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "departments_access" ON departments;
CREATE POLICY "departments_access" ON departments
FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "schedules_access" ON schedules;
CREATE POLICY "schedules_access" ON schedules
FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "reviews_access" ON reviews;
CREATE POLICY "reviews_access" ON reviews
FOR ALL USING (auth.uid() IS NOT NULL);

-- Password reset tokens: проверяем наличие establishment_id
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'password_reset_tokens'
    AND column_name = 'establishment_id'
    AND table_schema = 'public'
  ) THEN
    -- Есть establishment_id
    DROP POLICY IF EXISTS "password_reset_tokens_owner_access" ON password_reset_tokens;
    CREATE POLICY "password_reset_tokens_owner_access" ON password_reset_tokens
    FOR ALL USING (establishment_id IN (
      SELECT establishment_id FROM employees
      WHERE id = auth.uid() AND 'owner' = ANY(roles)
    ));
  ELSE
    -- Нет establishment_id - только владельцы
    DROP POLICY IF EXISTS "password_reset_tokens_owner_global" ON password_reset_tokens;
    CREATE POLICY "password_reset_tokens_owner_global" ON password_reset_tokens
    FOR ALL USING (EXISTS (
      SELECT 1 FROM employees
      WHERE id = auth.uid() AND 'owner' = ANY(roles)
    ));
  END IF;
END $$;

-- =============================================================================
-- ПРОВЕРКА
-- =============================================================================

-- Проверить статус RLS:
-- SELECT schemaname, tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;