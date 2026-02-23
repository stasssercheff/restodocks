#!/bin/bash
set -e

# Скрипт восстановления базы данных PostgreSQL из бэкапа

echo "🗄️ ВОССТАНОВЛЕНИЕ БАЗЫ ДАННЫХ RESTODOCKS"
echo "=========================================="

# Проверяем наличие дампа БД
DB_DUMP=""
if [ -f "database.sql.gz" ]; then
    DB_DUMP="database.sql.gz"
    echo "📦 Найден сжатый дамп: database.sql.gz"
elif [ -f "database.sql" ]; then
    DB_DUMP="database.sql"
    echo "📦 Найден дамп: database.sql"
else
    echo "❌ ДАМП БАЗЫ ДАННЫХ НЕ НАЙДЕН!"
    echo ""
    echo "📋 ВАРИАНТЫ:"
    echo "1. Распакуйте архив бэкапа:"
    echo "   tar -xzf backup_*_COMPLETE.tar.gz"
    echo "2. Скопируйте database.sql.gz из архива"
    echo "3. Распакуйте: gunzip database.sql.gz"
    echo ""
    echo "💡 ИЛИ создайте новый бэкап с базой данных:"
    echo "   ./backup_all.sh (после настройки pg_dump)"
    exit 1
fi

# Проверяем настройки подключения
if [ ! -f "backup_config.env" ]; then
    echo "❌ Файл backup_config.env не найден!"
    echo "Запустите ./setup_db_password.sh для настройки"
    exit 1
fi

source backup_config.env

if [[ "$SUPABASE_DB_URL" == *"YOUR_DB_PASSWORD_HERE"* ]]; then
    echo "❌ Пароль базы данных не настроен!"
    echo "Запустите ./setup_db_password.sh"
    exit 1
fi

echo "🔗 URL БАЗЫ ДАННЫХ: $SUPABASE_DB_URL"
echo ""

# Распаковываем дамп если нужно
if [[ "$DB_DUMP" == *.gz ]]; then
    echo "📦 Распаковка дампа..."
    gunzip -f "$DB_DUMP"
    DB_DUMP="${DB_DUMP%.gz}"
    echo "✅ Дамп распакован: $DB_DUMP"
fi

# Размер дампа
DUMP_SIZE=$(ls -lh "$DB_DUMP" | awk '{print $5}')
echo "📊 Размер дампа: $DUMP_SIZE"
echo ""

read -p "⚠️  ВНИМАНИЕ: Это ПЕРЕЗАПИШЕТ текущую базу данных! Продолжить? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Восстановление отменено"
    exit 1
fi

echo ""
echo "🔄 НАЧИНАЮ ВОССТАНОВЛЕНИЕ БАЗЫ ДАННЫХ..."
echo "=========================================="

# Восстанавливаем базу данных
echo "📥 Восстановление данных..."
if psql "$SUPABASE_DB_URL" < "$DB_DUMP" 2>&1; then
    echo ""
    echo "✅ БАЗА ДАННЫХ ВОССТАНОВЛЕНА УСПЕШНО!"
    echo ""
    echo "🎯 ДАЛЬНЕЙШИЕ ШАГИ:"
    echo "1. Запустите проверку: ./verify_database.sh"
    echo "2. Запустите тестирование: ./test_database.sh"
    echo "3. Проверьте приложение в браузере"
else
    echo ""
    echo "❌ ОШИБКА ВОССТАНОВЛЕНИЯ!"
    echo ""
    echo "Возможные причины:"
    echo "• Неправильный пароль"
    echo "• Проблемы с сетью"
    echo "• Поврежденный дамп"
    echo ""
    echo "Попробуйте:"
    echo "1. Проверьте пароль: ./check_supabase_setup.sh"
    echo "2. Повторно скачайте дамп из бэкапа"
    exit 1
fi

echo ""
echo "🎉 ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО!"
echo "📅 Время: $(date)"
echo "📁 Дамп: $DB_DUMP"