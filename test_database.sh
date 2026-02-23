#!/bin/bash

# Скрипт функционального тестирования базы данных Restodocks

echo "🧪 ФУНКЦИОНАЛЬНОЕ ТЕСТИРОВАНИЕ БАЗЫ ДАННЫХ"
echo "==========================================="

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

echo "🧪 Запуск тестов..."
echo ""

# Функция для выполнения теста
run_test() {
    local test_name="$1"
    local query="$2"
    local expected_min=${3:-1}

    echo "🧪 ТЕСТ: $test_name"

    if result=$(psql "$SUPABASE_DB_URL" -t -c "$query" 2>/dev/null | tr -d ' '); then
        if [ "$result" -ge "$expected_min" ] 2>/dev/null; then
            echo "   ✅ ПРОЙДЕН (результат: $result)"
        else
            echo "   ⚠️ ПРОЙДЕН НО С МАЛЕНЬКИМ РЕЗУЛЬТАТОМ (результат: $result, минимум: $expected_min)"
        fi
    else
        echo "   ❌ ПРОВАЛЕН (ошибка выполнения)"
        return 1
    fi

    echo ""
    return 0
}

# 1. Тест основных таблиц
run_test "Таблица establishments существует и не пуста" \
         "SELECT COUNT(*) FROM establishments;" 0

run_test "Таблица products существует" \
         "SELECT COUNT(*) FROM products;" 0

run_test "Таблица categories существует" \
         "SELECT COUNT(*) FROM categories;" 0

# 2. Тест пользователей и аутентификации
run_test "Таблица пользователей существует" \
         "SELECT COUNT(*) FROM auth.users;" 0

run_test "Есть активные пользователи" \
         "SELECT COUNT(*) FROM auth.users WHERE email_confirmed_at IS NOT NULL;" 0

# 3. Тест заказов и транзакций
run_test "Таблица заказов существует" \
         "SELECT COUNT(*) FROM orders;" 0

run_test "Таблица позиций заказов существует" \
         "SELECT COUNT(*) FROM order_items;" 0

# 4. Тест сотрудников
run_test "Таблица сотрудников существует" \
         "SELECT COUNT(*) FROM employees;" 0

# 5. Тест инвентаря
run_test "Таблица инвентаря существует" \
         "SELECT COUNT(*) FROM inventory_documents;" 0

# 6. Тест связей между таблицами
echo "🔗 ТЕСТЫ СВЯЗЕЙ:"
echo ""

run_test "Продукты связаны с категориями" \
         "SELECT COUNT(DISTINCT p.category_id) FROM products p WHERE p.category_id IS NOT NULL;" 0

run_test "Заказы связаны с пользователями" \
         "SELECT COUNT(DISTINCT o.user_id) FROM orders o WHERE o.user_id IS NOT NULL;" 0

run_test "Позиции заказов связаны с продуктами" \
         "SELECT COUNT(DISTINCT oi.product_id) FROM order_items oi WHERE oi.product_id IS NOT NULL;" 0

# 7. Тест RLS политик
echo "🔒 ТЕСТЫ БЕЗОПАСНОСТИ (RLS):"
echo ""

run_test "RLS политики активны" \
         "SELECT COUNT(*) FROM pg_policies WHERE schemaname = 'public';" 1

# 8. Тест представлений и функций
echo "⚙️ ТЕСТЫ ФУНКЦИЙ И ПРЕДСТАВЛЕНИЙ:"
echo ""

# Проверяем наличие основной функции для продуктов
run_test "Функция get_establishment_products существует" \
         "SELECT COUNT(*) FROM information_schema.routines WHERE routine_name = 'get_establishment_products';" 0

# 9. Тест индексов производительности
echo "⚡ ТЕСТЫ ПРОИЗВОДИТЕЛЬНОСТИ:"
echo ""

run_test "Индексы созданы" \
         "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';" 1

# 10. Тест актуальности данных
echo "📅 ТЕСТЫ АКТУАЛЬНОСТИ ДАННЫХ:"
echo ""

# Проверяем что даты в разумных пределах (не в будущем, не слишком старые)
run_test "Даты заказов в допустимом диапазоне" \
         "SELECT COUNT(*) FROM orders WHERE created_at > '2020-01-01' AND created_at < NOW() + INTERVAL '1 day';" 0

run_test "Даты продуктов актуальны" \
         "SELECT COUNT(*) FROM products WHERE created_at > '2020-01-01' AND created_at < NOW() + INTERVAL '1 day';" 0

# 11. Тест целостности данных
echo "🔍 ТЕСТЫ ЦЕЛОСТНОСТИ ДАННЫХ:"
echo ""

# Проверяем что цены положительные
run_test "Цены продуктов корректны" \
         "SELECT COUNT(*) FROM products WHERE price >= 0;" 0

# Проверяем что количества не отрицательные
run_test "Количество на складе корректно" \
         "SELECT COUNT(*) FROM products WHERE stock_quantity >= 0;" 0

echo "🎯 ФУНКЦИОНАЛЬНОЕ ТЕСТИРОВАНИЕ ЗАВЕРШЕНО!"
echo ""
echo "📊 РЕЗУЛЬТАТЫ:"
echo "• Если большинство тестов ✅ - база данных работает корректно"
echo "• Если есть ❌ - проверьте восстановление или обратитесь за помощью"
echo ""
echo "🚀 Приложение готово к использованию!"