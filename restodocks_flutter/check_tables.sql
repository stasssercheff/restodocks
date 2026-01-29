-- Проверка существующих таблиц в базе данных
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;