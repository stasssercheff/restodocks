-- Тестовый скрипт для проверки создания таблиц
-- Выполните после настройки всех таблиц

-- Проверка существования таблиц
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('establishments', 'employees', 'products', 'cooking_processes', 'tech_cards', 'tt_ingredients')
ORDER BY table_name;

-- Проверка количества записей в cooking_processes
SELECT COUNT(*) as cooking_processes_count FROM cooking_processes;

-- Проверка структуры таблицы establishments
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'establishments'
ORDER BY ordinal_position;