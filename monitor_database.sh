#!/bin/bash

# Скрипт мониторинга состояния базы данных Restodocks

echo "📊 МОНИТОРИНГ БАЗЫ ДАННЫХ RESTODOCKS"
echo "====================================="
echo "📅 Время проверки: $(date)"
echo ""

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

# Функция для получения метрики
get_metric() {
    local query="$1"
    local label="$2"

    if result=$(psql "$SUPABASE_DB_URL" -t -c "$query" 2>/dev/null | tr -d ' '); then
        echo "   $label: $result"
    else
        echo "   $label: ОШИБКА"
    fi
}

echo "🗂️ ОБЩАЯ ИНФОРМАЦИЯ:"
get_metric "SELECT current_database();" "База данных"
get_metric "SELECT pg_size_pretty(pg_database_size(current_database()));" "Размер БД"
get_metric "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" "Количество таблиц"
get_metric "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'public';" "Количество функций"
echo ""

echo "👥 ПОЛЬЗОВАТЕЛИ И АУТЕНТИФИКАЦИЯ:"
get_metric "SELECT COUNT(*) FROM auth.users;" "Всего пользователей"
get_metric "SELECT COUNT(*) FROM auth.users WHERE email_confirmed_at IS NOT NULL;" "Подтвержденных email"
get_metric "SELECT COUNT(*) FROM auth.users WHERE last_sign_in_at > NOW() - INTERVAL '24 hours';" "Активных за 24ч"
echo ""

echo "🏪 УЧРЕЖДЕНИЯ И ПРОДУКТЫ:"
get_metric "SELECT COUNT(*) FROM establishments;" "Количество заведений"
get_metric "SELECT COUNT(*) FROM products;" "Количество продуктов"
get_metric "SELECT COUNT(*) FROM categories;" "Количество категорий"
get_metric "SELECT COUNT(*) FROM products WHERE stock_quantity = 0;" "Продуктов с нулевым остатком"
echo ""

echo "🛒 ЗАКАЗЫ И ПРОДАЖИ:"
get_metric "SELECT COUNT(*) FROM orders;" "Всего заказов"
get_metric "SELECT COUNT(*) FROM orders WHERE created_at > NOW() - INTERVAL '24 hours';" "Заказов за 24ч"
get_metric "SELECT COUNT(*) FROM order_items;" "Позиций в заказах"
get_metric "SELECT COALESCE(SUM(total_amount), 0) FROM orders WHERE created_at > NOW() - INTERVAL '24 hours';" "Выручка за 24ч"
echo ""

echo "👷 СОТРУДНИКИ:"
get_metric "SELECT COUNT(*) FROM employees;" "Количество сотрудников"
get_metric "SELECT COUNT(*) FROM employees WHERE is_active = true;" "Активных сотрудников"
get_metric "SELECT COUNT(DISTINCT role) FROM employees;" "Количество ролей"
echo ""

echo "📦 ИНВЕНТАРЬ:"
get_metric "SELECT COUNT(*) FROM inventory_documents;" "Документов инвентаризации"
get_metric "SELECT COUNT(*) FROM inventory_documents WHERE created_at > NOW() - INTERVAL '7 days';" "За неделю"
get_metric "SELECT COUNT(*) FROM inventory_history;" "Записей истории инвентаря"
echo ""

echo "🔒 БЕЗОПАСНОСТЬ:"
get_metric "SELECT COUNT(*) FROM pg_policies;" "Политик RLS"
get_metric "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = 'public';" "Триггеров"
get_metric "SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';" "Индексов"
echo ""

echo "⚡ ПРОИЗВОДИТЕЛЬНОСТЬ:"
get_metric "SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active';" "Активных подключений"
get_metric "SELECT COALESCE(EXTRACT(epoch FROM (SELECT avg(now() - query_start) FROM pg_stat_activity WHERE state = 'active')), 0);" "Среднее время запроса (сек)"

# Проверка долгих запросов
echo "   Долгие запросы (>30 сек):"
psql "$SUPABASE_DB_URL" -c "
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '30 seconds'
    AND state = 'active'
ORDER BY now() - pg_stat_activity.query_start DESC
LIMIT 3;
" 2>/dev/null || echo "   Не удалось проверить долгие запросы"

echo ""

echo "🔍 ПОСЛЕДНИЕ ОШИБКИ (logs):"
# Здесь можно добавить проверку логов, но в Supabase это ограничено

echo ""
echo "✅ МОНИТОРИНГ ЗАВЕРШЕН!"
echo "📅 Следующая проверка рекомендуется через 1-24 часа"
echo ""
echo "💡 Для регулярного мониторинга добавьте в cron:"
echo "   0 */6 * * * $(pwd)/monitor_database.sh >> database_monitor.log 2>&1"