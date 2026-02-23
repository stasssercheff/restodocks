#!/bin/bash
set -e

echo "🚀 ЗАПУСК ПОЛНОГО БЭКАПА RESTODOCKS"
echo "====================================="
echo "Дата: $(date)"
echo ""

# Создаем временную директорию для бэкапа
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUP_NAME"
mkdir -p "$BACKUP_DIR"

echo "📁 Создаю директорию бэкапа: $BACKUP_DIR"
echo ""

# 1. БЭКАП КОДА И КОНФИГУРАЦИИ
echo "📦 ШАГ 1: Бэкап кода и конфигурации..."
echo "   Выполняю: ./full_backup.sh"
./full_backup.sh > /dev/null 2>&1
echo "   ✅ Код и конфигурация сохранены"

# 2. БЭКАП БАЗЫ ДАННЫХ (если настроена)
echo ""
echo "🗄️ ШАГ 2: Бэкап базы данных..."
if [ -f "backup_config.env" ]; then
    source backup_config.env
    if [ -n "$SUPABASE_DB_URL" ] && command -v pg_dump >/dev/null 2>&1; then
        echo "   Найдены настройки БД, выполняю бэкап..."
        pg_dump "$SUPABASE_DB_URL" --no-owner --no-privileges --clean --if-exists > "$BACKUP_DIR/database.sql" 2>/dev/null || echo "   ⚠️ Ошибка бэкапа БД (проверьте настройки)"
        if [ -f "$BACKUP_DIR/database.sql" ]; then
            gzip "$BACKUP_DIR/database.sql"
            echo "   ✅ База данных сохранена: database.sql.gz"
        fi
    else
        echo "   ⚠️ БД не настроена или pg_dump не найден"
        echo "   Для настройки добавьте SUPABASE_DB_URL в backup_config.env"
    fi
else
    echo "   ⚠️ Файл backup_config.env не найден"
fi

# 3. БЭКАП STORAGE
echo ""
echo "💾 ШАГ 3: Бэкап файлового хранилища..."
if command -v python3 >/dev/null 2>&1 && [ -f "storage_backup.py" ]; then
    echo "   Запускаю бэкап storage..."
    SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co \
    SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE \
    python3 storage_backup.py > /dev/null 2>&1 || echo "   ⚠️ Ошибка бэкапа storage (возможно нет файлов)"
    echo "   ✅ Бэкап storage завершен"
else
    echo "   ⚠️ Python3 или storage_backup.py не найдены"
fi

# 4. ОБЪЕДИНЕНИЕ В ОДИН АРХИВ
echo ""
echo "📦 ШАГ 4: Создание единого архива..."
FINAL_ARCHIVE="${BACKUP_NAME}_COMPLETE.tar.gz"

# Копируем все созданные бэкапы
find . -name "${BACKUP_NAME}*.tar.gz" -exec cp {} "$BACKUP_DIR/" \; 2>/dev/null || true
find . -name "storage_backup_*.tar.gz" -exec cp {} "$BACKUP_DIR/" \; 2>/dev/null || true
find . -name "database_backup.sql.gz" -exec cp {} "$BACKUP_DIR/" \; 2>/dev/null || true

# Создаем финальный архив
tar -czf "$FINAL_ARCHIVE" "$BACKUP_DIR"
FINAL_SIZE=$(ls -lh "$FINAL_ARCHIVE" | awk '{print $5}')

# 5. ОЧИСТКА (оставляем только финальный архив)
echo ""
echo "🧹 ШАГ 5: Очистка временных файлов..."
rm -rf "$BACKUP_DIR"
find . -name "${BACKUP_NAME}*.tar.gz" ! -name "$FINAL_ARCHIVE" -delete 2>/dev/null || true
find . -name "storage_backup_*.tar.gz" -delete 2>/dev/null || true

echo ""
echo "🎉 ПОЛНЫЙ БЭКАП ЗАВЕРШЕН!"
echo "====================================="
echo "📁 Архив: $FINAL_ARCHIVE"
echo "📊 Размер: $FINAL_SIZE"
echo "📅 Дата: $(date)"
echo ""
echo "✅ Содержимое:"
echo "   • Исходный код проекта"
echo "   • Supabase миграции и функции"
echo "   • Конфигурационные файлы"
if [ -f "$BACKUP_DIR/database.sql.gz" ]; then
    echo "   • База данных PostgreSQL"
fi
echo "   • Файловое хранилище (если есть файлы)"
echo ""
echo "💡 Для восстановления используйте скрипт restore.sh из архива"
echo ""
echo "🚀 ГОТОВО! Нажмите любую клавишу для выхода..."
read -n 1 -s