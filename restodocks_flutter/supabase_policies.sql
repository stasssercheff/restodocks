-- ЧАСТЬ 3: Настройка безопасности (RLS)
-- Выполните после вставки данных

-- Включение RLS для таблиц
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Политики для establishments
CREATE POLICY "Users can view their own establishment" ON establishments
  FOR SELECT USING (auth.uid()::text = owner_id::text);

CREATE POLICY "Users can update their own establishment" ON establishments
  FOR UPDATE USING (auth.uid()::text = owner_id::text);

-- Политики для employees
CREATE POLICY "Users can view employees from their establishment" ON employees
  FOR SELECT USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );

CREATE POLICY "Users can manage employees from their establishment" ON employees
  FOR ALL USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );

-- Политики для products (доступны всем аутентифицированным)
CREATE POLICY "Authenticated users can view products" ON products
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can manage products" ON products
  FOR ALL TO authenticated USING (true);

-- Политики для tech_cards
CREATE POLICY "Users can view tech cards from their establishment" ON tech_cards
  FOR SELECT USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );

CREATE POLICY "Users can manage tech cards from their establishment" ON tech_cards
  FOR ALL USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );

-- Политики для tt_ingredients
CREATE POLICY "Users can view ingredients from their establishment" ON tt_ingredients
  FOR SELECT USING (
    tech_card_id IN (
      SELECT id FROM tech_cards WHERE establishment_id IN (
        SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
      )
    )
  );

CREATE POLICY "Users can manage ingredients from their establishment" ON tt_ingredients
  FOR ALL USING (
    tech_card_id IN (
      SELECT id FROM tech_cards WHERE establishment_id IN (
        SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
      )
    )
  );

-- Политики для establishment_products
CREATE POLICY "Users can view establishment products from their establishment" ON establishment_products
  FOR SELECT USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );

CREATE POLICY "Users can manage establishment products from their establishment" ON establishment_products
  FOR ALL USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id::text = auth.uid()::text
    )
  );