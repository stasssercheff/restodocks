-- ПРАВИЛЬНЫЕ ПОЛИТИКИ RLS ДЛЯ ЗАЩИТЫ ДАННЫХ
-- Выполнить после включения RLS на таблицах

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ЗАВЕДЕНИЙ И СОТРУДНИКОВ
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

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ПРОДУКТОВ И ТТК (глобальные таблицы)
-- =============================================================================

-- Products: глобальная таблица, все авторизованные пользователи видят всё
-- (можно ограничить по поставщикам или категориям позже)
DROP POLICY IF EXISTS "products_access" ON products;
CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

-- Cooking processes: глобальные технологические процессы
DROP POLICY IF EXISTS "cooking_processes_access" ON cooking_processes;
CREATE POLICY "cooking_processes_access" ON cooking_processes
FOR ALL USING (auth.uid() IS NOT NULL);

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ЗАВЕДЕНИЙ
-- =============================================================================

-- Tech cards: ТТК конкретного заведения
DROP POLICY IF EXISTS "tech_cards_establishment_access" ON tech_cards;
CREATE POLICY "tech_cards_establishment_access" ON tech_cards
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- TT ingredients: ингредиенты ТТК (доступ через tech_card_id)
DROP POLICY IF EXISTS "tt_ingredients_tech_card_access" ON tt_ingredients;
CREATE POLICY "tt_ingredients_tech_card_access" ON tt_ingredients
FOR ALL USING (tech_card_id IN (
  SELECT id FROM tech_cards WHERE establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
));

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ЧЕКЛИСТОВ
-- =============================================================================

-- Checklists: чеклисты конкретного заведения
DROP POLICY IF EXISTS "checklists_establishment_access" ON checklists;
CREATE POLICY "checklists_establishment_access" ON checklists
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Checklist items: пункты чеклистов (доступ через checklist_id)
DROP POLICY IF EXISTS "checklist_items_checklist_access" ON checklist_items;
CREATE POLICY "checklist_items_checklist_access" ON checklist_items
FOR ALL USING (checklist_id IN (
  SELECT id FROM checklists WHERE establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
));

-- Checklist submissions: отправленные чеклисты (шеф видит отправленные ему)
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
CREATE POLICY "checklist_submissions_recipient_access" ON checklist_submissions
FOR ALL USING (recipient_chef_id = auth.uid());

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ЗАКАЗОВ И ДОКУМЕНТОВ
-- =============================================================================

-- Order documents: документы заказов конкретного заведения
DROP POLICY IF EXISTS "order_documents_establishment_access" ON order_documents;
CREATE POLICY "order_documents_establishment_access" ON order_documents
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ГЛОБАЛЬНЫХ СПРАВОЧНИКОВ
-- =============================================================================

-- Roles: глобальные роли (все авторизованные пользователи видят)
DROP POLICY IF EXISTS "roles_access" ON roles;
CREATE POLICY "roles_access" ON roles
FOR ALL USING (auth.uid() IS NOT NULL);

-- Departments: глобальные отделы (все авторизованные пользователи видят)
DROP POLICY IF EXISTS "departments_access" ON departments;
CREATE POLICY "departments_access" ON departments
FOR ALL USING (auth.uid() IS NOT NULL);

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ГРАФИКОВ И ОТЗЫВОВ
-- =============================================================================

-- Schedules: графики конкретного заведения (нужно добавить колонку establishment_id)
-- NOTE: Если schedules не имеет establishment_id, политика будет другой
DROP POLICY IF EXISTS "schedules_establishment_access" ON schedules;
CREATE POLICY "schedules_establishment_access" ON schedules
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Reviews: отзывы конкретного заведения (нужно добавить колонку establishment_id)
DROP POLICY IF EXISTS "reviews_establishment_access" ON reviews;
CREATE POLICY "reviews_establishment_access" ON reviews
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- =============================================================================
-- ПОЛИТИКИ ДЛЯ ЧУВСТВИТЕЛЬНЫХ ДАННЫХ
-- =============================================================================

-- Password reset tokens: только владелец может управлять токенами своего заведения
DROP POLICY IF EXISTS "password_reset_tokens_owner_access" ON password_reset_tokens;
CREATE POLICY "password_reset_tokens_owner_access" ON password_reset_tokens
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees
  WHERE id = auth.uid() AND 'owner' = ANY(roles)
));

-- =============================================================================
-- ПРОВЕРКА
-- =============================================================================

-- После применения политик можно проверить:
-- SELECT schemaname, tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND rowsecurity = true;