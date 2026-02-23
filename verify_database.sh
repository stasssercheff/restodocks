#!/bin/bash

# Скрипт проверки состояния базы данных после восстановления

echo "🔍 ПРОВЕРКА СОСТОЯНИЯ БАЗЫ ДАННЫХ RESTODOCKS"
echo "=============================================="

# Проверяем настройки
if [ ! -f "backup_config.env" ]; then
    echo "❌ backup_config.env не найден!"
    exit 1
fi

source backup_config.env

if [[ "$SUPABASE_DB_URL" == *"YOUR_DB_PASSWORD_HERE"* ]]; then
    echo "❌ Пароль не настроен!"
    exit 1
fi

echo "🧪 Выполняю проверки..."
echo ""

# Функция для выполнения SQL запросов
execute_sql() {
    local query="$1"
    local description="$2"
    echo "📋 $description"

    if result=$(psql "$SUPABASE_DB_URL" -t -c "$query" 2>/dev/null); then
        echo "   ✅ $result"
    else
        echo "   ❌ Ошибка выполнения запроса"
        return 1
    fi
}

# 1. Проверка подключения
echo "1️⃣ ПОДКЛЮЧЕНИЕ К БД:"
execute_sql "SELECT version();" "Версия PostgreSQL"
execute_sql "SELECT current_database();" "Текущая база данных"
execute_sql "SELECT current_user;" "Текущий пользователь"
echo ""

# 2. Проверка таблиц
echo "2️⃣ ПРОВЕРКА ТАБЛИЦ:"
execute_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" "Количество таблиц в схеме public"
execute_sql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;" "Список таблиц"
echo ""

# 3. Проверка ключевых таблиц
echo "3️⃣ КЛЮЧЕВЫЕ ТАБЛИЦЫ:"
TABLES=("establishments" "products" "users" "orders" "employees" "categories")

for table in "${TABLES[@]}"; do
    if execute_sql "SELECT COUNT(*) FROM $table;" "Записи в таблице $table" 2>/dev/null; then
        :
    else
        echo "   ⚠️ Таблица $table не найдена или пуста"
    fi
done
echo ""

# 4. Проверка индексов
echo "4️⃣ ИНДЕКСЫ:"
execute_sql "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';" "Количество индексов"
execute_sql "SELECT indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY indexname LIMIT 5;" "Примеры индексов"
echo ""

# 5. Проверка политик RLS
echo "5️⃣ ПОЛИТИКИ RLS:"
execute_sql "SELECT COUNT(*) FROM pg_policies;" "Количество политик безопасности"
execute_sql "SELECT schemaname, tablename, policyname FROM pg_policies ORDER BY tablename;" "Список политик"
echo ""

# 6. Проверка триггеров
echo "6️⃣ ТРИГГЕРЫ:"
execute_sql "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = 'public';" "Количество триггеров"
execute_sql "SELECT trigger_name, event_manipulation, event_object_table FROM information_schema.triggers WHERE trigger_schema = 'public' ORDER BY event_object_table;" "Список триггеров"
echo ""

# 7. Проверка функций
echo "7️⃣ ФУНКЦИИ:"
execute_sql "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'public' AND routine_type = 'FUNCTION';" "Количество функций"
execute_sql "SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public' AND routine_type = 'FUNCTION' ORDER BY routine_name;" "Список функций"
echo ""

# 8. Проверка представлений
echo "8️⃣ ПРЕДСТАВЛЕНИЯ:"
execute_sql "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'public';" "Количество представлений"
execute_sql "SELECT table_name FROM information_schema.views WHERE table_schema = 'public' ORDER BY table_name;" "Список представлений"
echo ""

# 9. Проверка размера базы данных
echo "9️⃣ РАЗМЕР БАЗЫ ДАННЫХ:"
execute_sql "SELECT pg_size_pretty(pg_database_size(current_database()));" "Общий размер БД"
execute_sql "SELECT schemaname, pg_size_pretty(sum(pg_relation_size(quote_ident(schemaname)||'.'||quote_ident(tablename)))::bigint) as size FROM pg_tables WHERE schemaname = 'public' GROUP BY schemaname ORDER BY sum(pg_relation_size(quote_ident(schemaname)||'.'||quote_ident(tablename))) DESC LIMIT 5;" "Размеры таблиц"
echo ""

# 10. Проверка связей (foreign keys)
echo "🔟 СВЯЗИ МЕЖДУ ТАБЛИЦАМИ:"
execute_sql "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type = 'FOREIGN KEY' AND table_schema = 'public';" "Количество внешних ключей"
execute_sql "SELECT tc.table_name, kcu.column_name, ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name FROM information_schema.table_constraints AS tc JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name WHERE constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public' LIMIT 5;" "Примеры связей"
echo ""

echo "🎯 ПРОВЕРКА ЗАВЕРШЕНА!"
echo ""
echo "📊 Если все проверки прошли успешно - база данных восстановлена корректно!"
echo ""
echo "🧪 Рекомендуется запустить функциональное тестирование:"
echo "   ./test_database.sh"