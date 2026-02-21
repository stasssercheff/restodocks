-- ЧИСТАЯ НАСТРОЙКА БАЗЫ ДАННЫХ С РАБОЧИМИ RLS ПОЛИТИКАМИ

-- =============================================================================
-- 1. ВКЛЮЧАЕМ RLS НА ВСЕХ ТАБЛИЦАХ
-- =============================================================================

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_reset_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE cooking_processes ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- 2. УДАЛЯЕМ ВСЕ СТАРЫЕ ПОЛИТИКИ
-- =============================================================================

-- Получаем список всех политик для удаления
DO $$
DECLARE
    pol record;
BEGIN
    FOR pol IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                       pol.policyname, pol.schemaname, pol.tablename);
    END LOOP;
END $$;

-- =============================================================================
-- 3. СОЗДАЕМ РАБОЧИЕ ПОЛИТИКИ
-- =============================================================================

-- Глобальные таблицы (доступны всем авторизованным пользователям)
CREATE POLICY "products_global_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

CREATE POLICY "cooking_processes_global_access" ON cooking_processes
FOR ALL USING (auth.uid() IS NOT NULL);

CREATE POLICY "roles_global_access" ON roles
FOR ALL USING (auth.uid() IS NOT NULL);

-- Заведения и сотрудники (строго по принадлежности)
CREATE POLICY "establishments_owner_access" ON establishments
FOR ALL USING (id IN (
  SELECT establishment_id FROM employees
  WHERE id = auth.uid() AND 'owner' = ANY(roles)
));

CREATE POLICY "employees_establishment_access" ON employees
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
) OR id = auth.uid());

-- Продукты заведения
CREATE POLICY "establishment_products_access" ON establishment_products
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- ТТК и ингредиенты
CREATE POLICY "tech_cards_establishment_access" ON tech_cards
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

CREATE POLICY "tt_ingredients_access" ON tt_ingredients
FOR ALL USING (tech_card_id IN (
  SELECT id FROM tech_cards WHERE establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
));

-- Чеклисты
CREATE POLICY "checklists_establishment_access" ON checklists
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

CREATE POLICY "checklist_items_access" ON checklist_items
FOR ALL USING (checklist_id IN (
  SELECT id FROM checklists WHERE establishment_id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  )
));

CREATE POLICY "checklist_submissions_access" ON checklist_submissions
FOR ALL USING (recipient_chef_id = auth.uid() OR establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Документы заказов
CREATE POLICY "order_documents_establishment_access" ON order_documents
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Отзывы
CREATE POLICY "reviews_establishment_access" ON reviews
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Отделы
CREATE POLICY "departments_establishment_access" ON departments
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Расписания
CREATE POLICY "schedules_establishment_access" ON schedules
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Токены сброса пароля (только свои)
CREATE POLICY "password_reset_tokens_own_access" ON password_reset_tokens
FOR ALL USING (employee_id = auth.uid());

-- =============================================================================
-- 4. ДОПОЛНИТЕЛЬНЫЕ ПОЛИТИКИ ДЛЯ АНОНИМНОГО ДОСТУПА (РЕГИСТРАЦИЯ)
-- =============================================================================

-- Анонимные пользователи могут искать сотрудников по email для регистрации
CREATE POLICY "anon_select_employees" ON employees
FOR SELECT USING (true);

-- Анонимные пользователи могут искать заведения по PIN
CREATE POLICY "anon_select_establishments" ON establishments
FOR SELECT USING (true);

-- Анонимные пользователи могут создавать сотрудников и заведения при регистрации
CREATE POLICY "anon_insert_employees" ON employees
FOR INSERT WITH CHECK (true);

CREATE POLICY "anon_insert_establishments" ON establishments
FOR INSERT WITH CHECK (true);

-- =============================================================================
-- 5. ПРОВЕРКА
-- =============================================================================

SELECT
    tablename,
    COUNT(*) as policies_count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY tablename;