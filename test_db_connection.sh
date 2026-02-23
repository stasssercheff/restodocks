#!/bin/bash

echo "🧪 ТЕСТИРОВАНИЕ ПОДКЛЮЧЕНИЯ К БАЗЕ ДАННЫХ SUPABASE"
echo "=================================================="

# Загружаем конфигурацию
if [ ! -f "backup_config.env" ]; then
    echo "❌ Файл backup_config.env не найден!"
    exit 1
fi

source backup_config.env

# Проверяем, настроен ли пароль
if [[ "$SUPABASE_DB_URL" == *"YOUR_DB_PASSWORD_HERE"* ]]; then
    echo "❌ Пароль базы данных не настроен!"
    echo ""
    echo "📋 ИНСТРУКЦИЯ:"
    echo "1. Откройте https://app.supabase.com"
    echo "2. Выберите проект osglfptwbuqqmqunttha"
    echo "3. Settings → Database → Database password"
    echo "4. Скопируйте пароль"
    echo "5. Вставьте в backup_config.env вместо YOUR_DB_PASSWORD_HERE"
    echo ""
    echo "Пример:"
    echo 'SUPABASE_DB_URL=postgresql://postgres:ВАШ_ПАРОЛЬ_ЗДЕСЬ@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres'
    exit 1
fi

echo "🔍 Проверяю pg_dump..."
if ! command -v pg_dump >/dev/null 2>&1; then
    echo "❌ pg_dump не найден. Устанавливаю через pip..."
    python3 -m pip install --user psycopg2-binary
fi

echo "🔗 Тестирую подключение к БД..."
echo "URL: $SUPABASE_DB_URL"
echo ""

# Тестируем подключение
if pg_dump "$SUPABASE_DB_URL" --version > /dev/null 2>&1; then
    echo "✅ ПОДКЛЮЧЕНИЕ УСПЕШНО!"
    echo ""
    echo "🎉 База данных готова для бэкапа!"
    echo "Теперь ./backup_all.sh будет включать бэкап БД"
else
    echo "❌ ОШИБКА ПОДКЛЮЧЕНИЯ!"
    echo ""
    echo "Возможные причины:"
    echo "• Неправильный пароль"
    echo "• Блокировка IP-адреса"
    echo "• Проблемы с сетью"
    echo ""
    echo "Проверьте пароль еще раз в Supabase Dashboard"
fi