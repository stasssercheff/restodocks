#!/bin/bash

# Скрипт диагностики проблем базы данных Restodocks

echo "🔧 ДИАГНОСТИКА ПРОБЛЕМ БАЗЫ ДАННЫХ"
echo "==================================="
echo "📅 Время: $(date)"
echo ""

# Проверяем настройки
if [ ! -f "backup_config.env" ]; then
    echo "❌ Файл backup_config.env не найден!"
    echo "Запустите ./setup_db_password.sh"
    exit 1
fi

source backup_config.env

if [[ "$SUPABASE_DB_URL" == *"YOUR_DB_PASSWORD_HERE"* ]]; then
    echo "❌ Пароль базы данных не настроен!"
    echo "Запустите ./setup_db_password.sh"
    exit 1
fi

echo "🔍 Выполняю диагностику..."
echo ""

# Функция для диагностики
diagnose() {
    local test_name="$1"
    local query="$2"
    local issue_description="$3"

    echo "🩺 $test_name"

    if result=$(psql "$SUPABASE_DB_URL" -t -c "$query" 2>&1); then
        if [ $? -eq 0 ]; then
            echo "   ✅ OK"
        else
            echo "   ❌ ПРОБЛЕМА: $issue_description"
            echo "   Детали: $result"
        fi
    else
        echo "   ❌ НЕ УДАЛОСЬ ВЫПОЛНИТЬ: $issue_description"
        echo "   Ошибка: $result"
    fi
    echo ""
}

# 1. Проверка подключения
diagnose "ПОДКЛЮЧЕНИЕ К БАЗЕ ДАННЫХ" \
         "SELECT 1;" \
         "Не удается подключиться к базе данных. Проверьте пароль и URL."

# 2. Проверка основных таблиц
diagnose "ТАБЛИЦА ESTABLISHMENTS" \
         "SELECT COUNT(*) FROM establishments;" \
         "Таблица establishments отсутствует или повреждена."

diagnose "ТАБЛИЦА PRODUCTS" \
         "SELECT COUNT(*) FROM products;" \
         "Таблица products отсутствует или повреждена."

diagnose "ТАБЛИЦА USERS" \
         "SELECT COUNT(*) FROM auth.users;" \
         "Таблица пользователей отсутствует. Проверьте аутентификацию."

# 3. Проверка RLS политик
echo "🔒 ДИАГНОСТИКА RLS ПОЛИТИК:"
echo ""

# Проверяем, что политики существуют
diagnose "RLS ПОЛИТИКИ ПРОДУКТОВ" \
         "SELECT COUNT(*) FROM pg_policies WHERE tablename = 'products';" \
         "Отсутствуют политики безопасности для продуктов."

diagnose "RLS ПОЛИТИКИ ЗАКАЗОВ" \
         "SELECT COUNT(*) FROM pg_policies WHERE tablename = 'orders';" \
         "Отсутствуют политики безопасности для заказов."

# Проверяем, что политики работают корректно
echo "🧪 ТЕСТИРОВАНИЕ RLS:"
psql "$SUPABASE_DB_URL" -c "
DO $$
BEGIN
    -- Тест: попытка доступа без аутентификации
    SET LOCAL auth.jwt.claims TO '{}';
    BEGIN
        PERFORM COUNT(*) FROM products LIMIT 1;
        RAISE NOTICE 'RLS: Доступ без аутентификации - ЗАБЛОКИРОВАН ✅';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'RLS: Доступ без аутентификации - ЗАБЛОКИРОВАН ✅';
    END;

    -- Тест: проверка что суперпользователь имеет доступ
    SET LOCAL auth.jwt.claims TO '{\"role\": \"service_role\"}';
    PERFORM COUNT(*) FROM products LIMIT 1;
    RAISE NOTICE 'RLS: Доступ суперпользователя - РАЗРЕШЕН ✅';

END $$;
" 2>/dev/null || echo "   ⚠️ Не удалось выполнить тест RLS"

echo ""

# 4. Проверка индексов
echo "⚡ ДИАГНОСТИКА ИНДЕКСОВ:"
echo ""

diagnose "ИНДЕКСЫ ПРОДУКТОВ" \
         "SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'products';" \
         "Отсутствуют индексы для таблицы products. Возможны проблемы с производительностью."

diagnose "ИНДЕКСЫ ЗАКАЗОВ" \
         "SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'orders';" \
         "Отсутствуют индексы для таблицы orders. Возможны проблемы с производительностью."

# 5. Проверка ограничений и связей
echo "🔗 ДИАГНОСТИКА СВЯЗЕЙ:"
echo ""

diagnose "ВНЕШНИЕ КЛЮЧИ" \
         "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type = 'FOREIGN KEY';" \
         "Отсутствуют связи между таблицами. Данные могут быть несогласованными."

# 6. Проверка триггеров
echo "⚙️ ДИАГНОСТИКА ТРИГГЕРОВ:"
echo ""

diagnose "ТРИГГЕРЫ ОБНОВЛЕНИЯ" \
         "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_name LIKE '%update%';" \
         "Отсутствуют триггеры обновления. Данные могут быть устаревшими."

# 7. Проверка места на диске
echo "💾 ДИАГНОСТИКА МЕСТА:"
echo ""

diagnose "РАЗМЕР БАЗЫ ДАННЫХ" \
         "SELECT pg_size_pretty(pg_database_size(current_database()));" \
         "Не удается определить размер базы данных."

# 8. Проверка последних ошибок
echo "🚨 ПОСЛЕДНИЕ ОШИБКИ:"
echo ""

# Проверяем системные логи (если доступны)
psql "$SUPABASE_DB_URL" -c "
SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE schemaname = 'public'
    AND tablename IN ('products', 'orders', 'establishments')
ORDER BY n_distinct DESC
LIMIT 5;
" 2>/dev/null || echo "   Не удалось получить статистику таблиц"

echo ""

# 9. Рекомендации
echo "💡 РЕКОМЕНДАЦИИ:"
echo ""

# Проверяем что все основные компоненты на месте
COMPONENTS_OK=true

# Проверяем основные таблицы
for table in establishments products categories orders employees; do
    if ! psql "$SUPABASE_DB_URL" -c "SELECT 1 FROM $table LIMIT 1;" >/dev/null 2>&1; then
        echo "   ❌ Таблица $table отсутствует или недоступна"
        COMPONENTS_OK=false
    fi
done

if [ "$COMPONENTS_OK" = true ]; then
    echo "   ✅ Все основные компоненты на месте"
else
    echo "   ⚠️ Некоторые компоненты отсутствуют. Рекомендуется переустановить базу данных."
fi

echo ""
echo "🎯 ДИАГНОСТИКА ЗАВЕРШЕНА!"
echo ""
echo "📋 ЕСЛИ ЕСТЬ ПРОБЛЕМЫ:"
echo "1. Запустите ./restore_database.sh для восстановления"
echo "2. Проверьте ./verify_database.sh для детальной проверки"
echo "3. Выполните ./test_database.sh для функционального тестирования"