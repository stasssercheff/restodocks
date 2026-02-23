#!/bin/bash

echo "🔍 ПРОВЕРКА НАСТРОЙКИ SUPABASE БЭКАПА"
echo "====================================="

# Проверяем наличие конфигурации
if [ ! -f "backup_config.env" ]; then
    echo "❌ backup_config.env не найден!"
    exit 1
fi

echo "📋 ТЕКУЩИЕ НАСТРОЙКИ:"
echo ""

# Показываем текущий URL
source backup_config.env
echo "SUPABASE_DB_URL: $SUPABASE_DB_URL"
echo ""

# Проверяем, настроен ли пароль
if [[ "$SUPABASE_DB_URL" == *"YOUR_DB_PASSWORD_HERE"* ]]; then
    echo "❌ ПАРОЛЬ НЕ НАСТРОЕН!"
    echo ""
    echo "🛠️ ЧТО ДЕЛАТЬ:"
    echo ""
    echo "1️⃣ ОТКРОЙТЕ SUPABASE DASHBOARD:"
    echo "   https://app.supabase.com"
    echo ""
    echo "2️⃣ ВЫБЕРИТЕ ПРОЕКТ:"
    echo "   osglfptwbuqqmqunttha"
    echo ""
    echo "3️⃣ ПЕРЕЙДИТЕ:"
    echo "   Database → CONFIGURATION → Settings"
    echo ""
    echo "4️⃣ НАЙДИТЕ:"
    echo "   Раздел 'Database settings'"
    echo "   Поле 'Database password'"
    echo "   Нажмите 👁 чтобы увидеть пароль"
    echo ""
    echo "5️⃣ ЗАПУСТИТЕ НАСТРОЙКУ:"
    echo "   ./setup_db_password.sh"
    echo ""
    echo "6️⃣ ВВЕДИТЕ СКОПИРОВАННЫЙ ПАРОЛЬ"
    echo ""
else
    echo "✅ ПАРОЛЬ НАСТРОЕН!"
    echo ""
    echo "🧪 ТЕСТИРУЮ ПОДКЛЮЧЕНИЕ..."

    if command -v pg_dump >/dev/null 2>&1; then
        if pg_dump "$SUPABASE_DB_URL" --version > /dev/null 2>&1; then
            echo "✅ ПОДКЛЮЧЕНИЕ РАБОТАЕТ!"
            echo ""
            echo "🎉 ГОТОВО К БЭКАПУ!"
            echo "Запустите: ./backup_all.sh"
        else
            echo "❌ ПРОБЛЕМА С ПОДКЛЮЧЕНИЕМ!"
            echo "Возможно неправильный пароль."
            echo "Проверьте в Supabase Dashboard еще раз."
        fi
    else
        echo "⚠️ pg_dump не найден, но пароль сохранен."
        echo "Бэкап будет работать без предварительного теста."
    fi
fi

echo ""
echo "💡 ПОДСКАЗКА: Пароль должен содержать буквы, цифры и символы"