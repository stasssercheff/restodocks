-- ПОЛНАЯ НАСТРОЙКА SUPABASE ДЛЯ FLUTTER ПРИЛОЖЕНИЯ RESTODOCKS
-- Выполните этот скрипт в SQL Editor Supabase Dashboard

-- ШАГ 1: Удаление существующих таблиц (если нужно начать заново)
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

-- ШАГ 3: Добавление базовых технологических процессов
INSERT INTO cooking_processes (name, localized_names, calorie_multiplier, protein_multiplier, fat_multiplier, carbs_multiplier, weight_loss_percentage, applicable_categories) VALUES
('Boiling', '{"ru": "Варка", "en": "Boiling"}', 0.95, 0.95, 0.90, 0.98, 25.0, ARRAY['vegetables', 'meat', 'fish', 'grains', 'pasta']),
('Frying', '{"ru": "Жарка", "en": "Frying"}', 1.10, 0.95, 1.20, 0.98, 15.0, ARRAY['meat', 'fish', 'vegetables']),
('Baking', '{"ru": "Запекание", "en": "Baking"}', 1.05, 0.98, 1.05, 0.97, 20.0, ARRAY['meat', 'fish', 'vegetables', 'dough']),
('Stewing', '{"ru": "Тушение", "en": "Stewing"}', 0.98, 0.97, 0.95, 0.99, 30.0, ARRAY['meat', 'vegetables']);

-- ШАГ 4: Проверка создания
SELECT '✅ НАСТРОЙКА ЗАВЕРШЕНА!' as status, COUNT(*) as tables_created
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('establishments', 'employees', 'products', 'cooking_processes', 'tech_cards', 'tt_ingredients');