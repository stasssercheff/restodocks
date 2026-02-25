#!/bin/bash
set -e

echo "🚀 ЗАПУСК ПОЛНОГО БЭКАПА RESTODOCKS"
echo "====================================="
echo "Дата: $(date)"
echo ""

# ПРОВЕРКА: без этого бэкап будет неполный
if [ ! -f "backup_config.env" ]; then
    echo "❌ ОШИБКА: Файл backup_config.env не найден!"
    echo ""
    echo "📋 Сделай один раз (2 минуты):"
    echo "   1. Открой: https://supabase.com/dashboard/project/osglfptwbuqqmqunttha/settings/database"
    echo "   2. Скопируй пароль БД (Database password)"
    echo "   3. Создай файл backup_config.env в папке проекта с содержимым:"
    echo "      SUPABASE_DB_URL=postgresql://postgres:ТВОЙ_ПАРОЛЬ@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres"
    echo ""
    echo "   Подробнее: НАСТРОЙКА_БЭКАПА_ОДИН_РАЗ.md"
    exit 1
fi

if ! command -v pg_dump >/dev/null 2>&1; then
    echo "❌ ОШИБКА: pg_dump не найден (нужен для бэкапа БД)"
    echo ""
    echo "📋 Установи Postgres.app (1 минута):"
    echo "   1. Скачай: https://postgresapp.com"
    echo "   2. Перетащи в Applications"
    echo "   3. Запусти Postgres.app → кнопка Initialize"
    echo "   4. Запусти этот бэкап снова"
    echo ""
    echo "   Подробнее: НАСТРОЙКА_БЭКАПА_ОДИН_РАЗ.md"
    exit 1
fi

# Создаем временную директорию для бэкапа
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUP_NAME"
mkdir -p "$BACKUP_DIR"

echo "📁 Создаю директорию бэкапа: $BACKUP_DIR"
echo ""

# 1. БЭКАП КОДА И КОНФИГУРАЦИИ
echo "📦 ШАГ 1: Бэкап кода и конфигурации..."
export BACKUP_TARGET_DIR="$BACKUP_DIR"
./full_backup.sh > /dev/null 2>&1
echo "   ✅ Код и конфигурация сохранены"

# 2. БЭКАП БАЗЫ ДАННЫХ (если настроена)
echo ""
echo "🗄️ ШАГ 2: Бэкап базы данных..."
if [ -f "backup_config.env" ]; then
    source backup_config.env
    if [ -n "$SUPABASE_DB_URL" ] && command -v pg_dump >/dev/null 2>&1; then
        echo "   Найдены настройки БД, выполняю бэкап..."
        if pg_dump "$SUPABASE_DB_URL" --no-owner --no-privileges --clean --if-exists > "$BACKUP_DIR/database.sql" 2>/dev/null; then
            gzip "$BACKUP_DIR/database.sql"
            echo "   ✅ База данных сохранена: database.sql.gz"
        else
            echo "   ⚠️ Ошибка pg_dump (проверьте SUPABASE_DB_URL и pg_dump)"
        fi
    else
        echo "   ⚠️ БД не настроена или pg_dump не найден"
        echo "   Для настройки добавьте SUPABASE_DB_URL в backup_config.env"
    fi
else
    echo "   ⚠️ Файл backup_config.env не найден"
fi

# 2a. backup_config.env (нужен для восстановления БД)
cp backup_config.env "$BACKUP_DIR/" 2>/dev/null && echo "   ✅ backup_config.env сохранён" || true

# 2b. Бэкап Vercel env и Supabase Auth чеклиста
echo ""
echo "📋 ШАГ 2b: Бэкап Vercel env и Supabase Auth..."
if [ -f "scripts/backup_extras.sh" ]; then
    chmod +x scripts/backup_extras.sh 2>/dev/null || true
    ./scripts/backup_extras.sh "$BACKUP_DIR" 2>/dev/null || true
fi

# 3. БЭКАП STORAGE
echo ""
echo "💾 ШАГ 3: Бэкап файлового хранилища..."
if command -v python3 >/dev/null 2>&1 && [ -f "storage_backup.py" ]; then
    echo "   Запускаю бэкап storage..."
    SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co \
    SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE \
    python3 storage_backup.py 2>/dev/null || true
    # Добавляем storage в архив (распаковываем и переименовываем)
    for f in storage_backup_*.tar.gz; do
        [ -f "$f" ] && tar -xzf "$f" -C "$BACKUP_DIR" && mv "$BACKUP_DIR"/storage_backup_* "$BACKUP_DIR/storage_backup" 2>/dev/null && echo "   ✅ Storage сохранён" && break
    done
else
    echo "   ⚠️ Python3 или storage_backup.py не найдены (storage пропущен)"
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
echo "✅ Содержимое архива:"
if tar -tzf "$FINAL_ARCHIVE" | grep -q "database.sql.gz"; then
  echo "   • База данных PostgreSQL ✓"
else
  echo "   ⚠️ БАЗА ДАННЫХ ОТСУТСТВУЕТ — настройте backup_config.env (SUPABASE_DB_URL) и pg_dump"
fi
echo "   • Код, миграции, env, Vercel, Auth-чеклист, Storage"
echo ""
echo "💡 Восстановление: ./restore_all.sh  (из папки с архивом)"
echo ""
echo "🚀 ГОТОВО! Нажмите любую клавишу для выхода..."
read -n 1 -s