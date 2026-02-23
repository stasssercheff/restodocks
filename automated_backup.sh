#!/bin/bash
set -e

# Автоматизированный бэкап Restodocks
# Запускать по cron: 0 2 * * * /path/to/automated_backup.sh

BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "🤖 Автоматизированный бэкап Restodocks: $(date)"

# Проверяем наличие необходимых инструментов (необязательно)
command -v pg_dump >/dev/null 2>&1 || echo "⚠️ pg_dump не найден. Бэкап БД будет пропущен."
command -v supabase >/dev/null 2>&1 || echo "⚠️ Supabase CLI не найден. Некоторые функции будут недоступны."

# Конфигурация (заполните свои данные)
SUPABASE_PROJECT_REF="osglfptwbuqqmqunttha"
SUPABASE_DB_URL="${SUPABASE_DB_URL:-}"  # Установите переменную окружения

# 1. Бэкап кода (ежедневный)
echo "📦 Бэкап репозитория..."
mkdir -p "$BACKUP_DIR"
if [ -d "restodocks_flutter" ]; then
    cd restodocks_flutter
    git fetch origin main
    git archive --format=tar.gz -o "../$BACKUP_DIR/code.tar.gz" origin/main
    cd ..
else
    git clone --depth 1 https://github.com/stasssercheff/restodocks.git "$BACKUP_DIR/code"
fi

# 2. Бэкап базы данных
if [ -n "$SUPABASE_DB_URL" ]; then
    echo "🗄️ Бэкап базы данных..."
    pg_dump "$SUPABASE_DB_URL" --no-owner --no-privileges --clean --if-exists > "$BACKUP_DIR/database.sql"

    # Сжатие SQL файла
    gzip "$BACKUP_DIR/database.sql"
    echo "✅ База данных сохранена: database.sql.gz"
else
    echo "⚠️ SUPABASE_DB_URL не установлена. Пропускаем бэкап БД."
    echo "   Установите: export SUPABASE_DB_URL='postgresql://postgres:PASSWORD@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres'"
fi

# 3. Бэкап Storage (каждый раз)
echo "💾 Бэкап хранилища..."
if command -v python3 >/dev/null 2>&1; then
    SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE python3 storage_backup.py
else
    echo "⚠️ Python3 не найден. Бэкап storage пропущен."
fi

# 4. Бэкап конфигурации
echo "⚙️ Бэкап конфигурации..."
cp -r restodocks_flutter/supabase/migrations "$BACKUP_DIR/migrations/" 2>/dev/null || true
cp -r restodocks_flutter/supabase/functions "$BACKUP_DIR/functions/" 2>/dev/null || true
find . -name "supabase*.sql" -exec cp {} "$BACKUP_DIR/config/" \; 2>/dev/null || true

# 5. Создание архива
echo "📦 Создание архива..."
tar -czf "${BACKUP_DIR}.tar.gz" "$BACKUP_DIR"

# 6. Очистка старых бэкапов - ОТКЛЮЧЕНА (чтобы сохранять все версии)

# 7. Отправка уведомления (опционально)
if command -v curl >/dev/null 2>&1 && [ -n "$BACKUP_WEBHOOK_URL" ]; then
    curl -X POST "$BACKUP_WEBHOOK_URL" \
         -H "Content-Type: application/json" \
         -d "{\"text\":\"✅ Restodocks backup completed: ${BACKUP_DIR}.tar.gz\"}"
fi

echo "✅ Ручной бэкап завершен: ${BACKUP_DIR}.tar.gz"
echo "📊 Размер: $(du -sh "${BACKUP_DIR}.tar.gz" | cut -f1)"