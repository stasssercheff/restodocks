-- ИСПРАВЛЕНИЕ RLS ПОЛИТИК ДЛЯ ВОССТАНОВЛЕНИЯ ДОСТУПА К ДАННЫМ

-- Сначала отключим RLS временно для проверки
ALTER TABLE employees DISABLE ROW LEVEL SECURITY;
ALTER TABLE establishments DISABLE ROW LEVEL SECURITY;
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products DISABLE ROW LEVEL SECURITY;
ALTER TABLE tech_cards DISABLE ROW LEVEL SECURITY;
ALTER TABLE checklists DISABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients DISABLE ROW LEVEL SECURITY;

-- Теперь включим правильные политики
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- 1. ЗАВЕДЕНИЯ - владелец видит свое заведение
-- =============================================================================
DROP POLICY IF EXISTS "establishments_owner_access" ON establishments;
CREATE POLICY "establishments_owner_access" ON establishments
FOR ALL USING (owner_id = auth.uid());

-- =============================================================================
-- 2. СОТРУДНИКИ - сотрудники видят коллег из своего заведения
-- =============================================================================
DROP POLICY IF EXISTS "employees_establishment_access" ON employees;
CREATE POLICY "employees_establishment_access" ON employees
FOR ALL USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  ) OR id = auth.uid()
);

-- =============================================================================
-- 3. ПРОДУКТЫ - глобальная таблица, все авторизованные видят
-- =============================================================================
DROP POLICY IF EXISTS "products_access" ON products;
CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

-- =============================================================================
-- 4. ПРОДУКТЫ ЗАВЕДЕНИЯ - продукты конкретного заведения
-- =============================================================================
DROP POLICY IF EXISTS "establishment_products_access" ON establishment_products;
CREATE POLICY "establishment_products_access" ON establishment_products
FOR ALL USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- =============================================================================
-- 5. ТТК - техкарты конкретного заведения
-- =============================================================================
DROP POLICY IF EXISTS "tech_cards_establishment_access" ON tech_cards;
CREATE POLICY "tech_cards_establishment_access" ON tech_cards
FOR ALL USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- =============================================================================
-- 6. ЧЕКЛИСТЫ - чеклисты конкретного заведения
-- =============================================================================
DROP POLICY IF EXISTS "checklists_establishment_access" ON checklists;
CREATE POLICY "checklists_establishment_access" ON checklists
FOR ALL USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- =============================================================================
-- 7. ЭЛЕМЕНТЫ ЧЕКЛИСТОВ - элементы чеклистов своего заведения
-- =============================================================================
DROP POLICY IF EXISTS "checklist_items_checklist_access" ON checklist_items;
CREATE POLICY "checklist_items_checklist_access" ON checklist_items
FOR ALL USING (
  checklist_id IN (
    SELECT id FROM checklists WHERE establishment_id IN (
      SELECT id FROM establishments WHERE owner_id = auth.uid()
    )
  )
);

-- =============================================================================
-- 8. ИНГРЕДИЕНТЫ ТТК - ингредиенты ТТК своего заведения
-- =============================================================================
DROP POLICY IF EXISTS "tt_ingredients_tech_card_access" ON tt_ingredients;
CREATE POLICY "tt_ingredients_tech_card_access" ON tt_ingredients
FOR ALL USING (
  tech_card_id IN (
    SELECT id FROM tech_cards WHERE establishment_id IN (
      SELECT id FROM establishments WHERE owner_id = auth.uid()
    )
  )
);

-- =============================================================================
-- 9. ПРОВЕРКА - какие политики установлены
-- =============================================================================
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;