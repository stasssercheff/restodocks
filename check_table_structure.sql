-- ПРОВЕРКА СТРУКТУРЫ ТАБЛИЦ
-- Выполните для проверки, какие таблицы имеют establishment_id

-- Список всех таблиц в public схеме
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Колонки establishment_id во всех таблицах
SELECT
  t.table_name,
  c.column_name,
  c.data_type,
  c.is_nullable
FROM information_schema.tables t
LEFT JOIN information_schema.columns c ON t.table_name = c.table_name AND c.column_name = 'establishment_id'
WHERE t.table_schema = 'public'
  AND t.table_type = 'BASE TABLE'
  AND c.column_name = 'establishment_id'
ORDER BY t.table_name;

-- Статус RLS на таблицах
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;