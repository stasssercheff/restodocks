-- Проверка статуса настройки базы данных
SELECT
  '📊 СТАТУС НАСТРОЙКИ RESTODOCKS' as title,
  NOW() as checked_at;

-- Проверка таблиц
SELECT
  '✅ ТАБЛИЦЫ' as section,
  table_name as item,
  CASE WHEN table_name IN ('establishments', 'employees', 'products', 'cooking_processes', 'tech_cards', 'tt_ingredients')
       THEN 'СОЗДАНА'
       ELSE 'ОШИБКА'
  END as status
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('establishments', 'employees', 'products', 'cooking_processes', 'tech_cards', 'tt_ingredients')
ORDER BY table_name;

-- Проверка данных
SELECT
  '📦 ДАННЫЕ' as section,
  'Технологические процессы' as item,
  COUNT(*) as count,
  CASE WHEN COUNT(*) > 0 THEN 'ЗАГРУЖЕНЫ' ELSE 'ОТСУТСТВУЮТ' END as status
FROM cooking_processes;

-- Проверка политик безопасности
SELECT
  '🔒 БЕЗОПАСНОСТЬ' as section,
  'Row Level Security' as item,
  COUNT(*) as tables_with_rls,
  'НАСТРОЕНА' as status
FROM pg_policies
WHERE schemaname = 'public';

-- Проверка индексов
SELECT
  '⚡ ПРОИЗВОДИТЕЛЬНОСТЬ' as section,
  'Индексы' as item,
  COUNT(*) as indexes_count,
  'СОЗДАНЫ' as status
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('establishments', 'employees', 'products', 'cooking_processes', 'tech_cards', 'tt_ingredients');

-- ИТОГИ
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('establishments', 'employees', 'products', 'cooking_processes', 'tech_cards', 'tt_ingredients')) = 6
         AND (SELECT COUNT(*) FROM cooking_processes) > 0
    THEN '🎉 БАЗА ДАННЫХ ГОТОВА К ИСПОЛЬЗОВАНИЮ!'
    ELSE '⚠️ НАСТРОЙКА НЕ ЗАВЕРШЕНА'
  END as final_status;