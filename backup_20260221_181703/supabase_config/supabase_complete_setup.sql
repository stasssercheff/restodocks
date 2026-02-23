-- ПОЛНАЯ НАСТРОЙКА SUPABASE ДЛЯ RESTODOCKS
-- Скопируйте и выполните этот скрипт целиком в SQL Editor Supabase

-- ШАГ 1: Удаление существующих таблиц (если есть)
DROP TABLE IF EXISTS tt_ingredients CASCADE;
DROP TABLE IF EXISTS tech_cards CASCADE;
DROP TABLE IF EXISTS cooking_processes CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS establishments CASCADE;

-- ШАГ 2: Создание таблиц
CREATE TABLE establishments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  pin_code TEXT NOT NULL UNIQUE,
  owner_id UUID,
  address TEXT,
  phone TEXT,
  email TEXT,
  default_currency TEXT DEFAULT 'RUB',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE employees (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  department TEXT NOT NULL,
  section TEXT,
  roles TEXT[] NOT NULL DEFAULT '{}',
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  personal_pin TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE products (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  names JSONB,
  calories REAL,
  protein REAL,
  fat REAL,
  carbs REAL,
  contains_gluten BOOLEAN,
  contains_lactose BOOLEAN,
  base_price REAL,
  currency TEXT,
  unit TEXT,
  supplier_ids UUID[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE cooking_processes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  localized_names JSONB,
  calorie_multiplier REAL NOT NULL DEFAULT 1.0,
  protein_multiplier REAL NOT NULL DEFAULT 1.0,
  fat_multiplier REAL NOT NULL DEFAULT 1.0,
  carbs_multiplier REAL NOT NULL DEFAULT 1.0,
  weight_loss_percentage REAL NOT NULL DEFAULT 0.0,
  applicable_categories TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE tech_cards (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  dish_name TEXT NOT NULL,
  dish_name_localized JSONB,
  category TEXT NOT NULL,
  portion_weight REAL NOT NULL DEFAULT 100.0,
  yield REAL NOT NULL DEFAULT 0.0,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE tt_ingredients (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID REFERENCES products(id),
  product_name TEXT NOT NULL,
  cooking_process_id UUID REFERENCES cooking_processes(id),
  cooking_process_name TEXT,
  gross_weight REAL NOT NULL,
  net_weight REAL NOT NULL,
  is_net_weight_manual BOOLEAN DEFAULT false,
  final_calories REAL NOT NULL DEFAULT 0,
  final_protein REAL NOT NULL DEFAULT 0,
  final_fat REAL NOT NULL DEFAULT 0,
  final_carbs REAL NOT NULL DEFAULT 0,
  cost REAL NOT NULL DEFAULT 0,
  tech_card_id UUID NOT NULL REFERENCES tech_cards(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ШАГ 3: Добавление базовых данных
INSERT INTO cooking_processes (name, localized_names, calorie_multiplier, protein_multiplier, fat_multiplier, carbs_multiplier, weight_loss_percentage, applicable_categories) VALUES
('Boiling', '{"ru": "Варка", "en": "Boiling"}', 0.95, 0.95, 0.90, 0.98, 25.0, ARRAY['vegetables', 'meat', 'fish', 'grains', 'pasta']),
('Frying', '{"ru": "Жарка", "en": "Frying"}', 1.10, 0.95, 1.20, 0.98, 15.0, ARRAY['meat', 'fish', 'vegetables']),
('Baking', '{"ru": "Запекание", "en": "Baking"}', 1.05, 0.98, 1.05, 0.97, 20.0, ARRAY['meat', 'fish', 'vegetables', 'dough']),
('Stewing', '{"ru": "Тушение", "en": "Stewing"}', 0.98, 0.97, 0.95, 0.99, 30.0, ARRAY['meat', 'vegetables']);

-- ШАГ 4: Настройка безопасности (RLS)
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE tt_ingredients ENABLE ROW LEVEL SECURITY;

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

-- Политики для products
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

-- ШАГ 5: Индексы для производительности
CREATE INDEX idx_employees_establishment_id ON employees(establishment_id);
CREATE INDEX idx_employees_email ON employees(email);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_tech_cards_establishment_id ON tech_cards(establishment_id);
CREATE INDEX idx_tt_ingredients_tech_card_id ON tt_ingredients(tech_card_id);

-- ШАГ 6: Функции и триггеры
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_establishments_updated_at BEFORE UPDATE ON establishments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tech_cards_updated_at BEFORE UPDATE ON tech_cards FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ШАГ 7: Проверка настройки
SELECT
  'УСПЕШНО! Созданы таблицы:' as status,
  COUNT(*) as tables_count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('establishments', 'employees', 'products', 'cooking_processes', 'tech_cards', 'tt_ingredients');