#!/bin/bash
set -e

# Чтобы pg_dump находился при запуске двойным щелчком (.command), а не только из терминала с .zshrc
if [ -d "/Applications/Postgres.app/Contents/Versions/latest/bin" ]; then
  export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"
fi

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

# Каждый бэкап — отдельная папка в backups/; удалил папку = удалил весь бэкап
BACKUPS_ROOT="backups"
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUPS_ROOT/$BACKUP_NAME"
mkdir -p "$BACKUP_DIR"

echo "📁 Папка бэкапа: $BACKUP_DIR"
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
        # Supabase требует SSL; если в URL нет sslmode — добавляем
        DUMP_URL="$SUPABASE_DB_URL"
        if [[ "$DUMP_URL" != *"sslmode="* ]]; then
            [[ "$DUMP_URL" == *"?"* ]] && DUMP_URL="${DUMP_URL}&sslmode=require" || DUMP_URL="${DUMP_URL}?sslmode=require"
        fi
        if pg_dump "$DUMP_URL" --no-owner --no-privileges --clean --if-exists > "$BACKUP_DIR/database.sql" 2>"$BACKUP_DIR/pg_dump_err.txt"; then
            gzip "$BACKUP_DIR/database.sql"
            echo "   ✅ База данных сохранена: database.sql.gz"
        else
            echo "   ⚠️ Ошибка pg_dump (проверьте SUPABASE_DB_URL и пароль БД)"
            [ -f "$BACKUP_DIR/pg_dump_err.txt" ] && echo "   Текст ошибки: $(cat "$BACKUP_DIR/pg_dump_err.txt")"
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

# 4. Копируем временные архивы в папку бэкапа и создаём один архив внутри неё
echo ""
echo "📦 ШАГ 4: Архив внутри папки бэкапа..."
find . -maxdepth 1 -name "storage_backup_*.tar.gz" -exec mv {} "$BACKUP_DIR/" \; 2>/dev/null || true
find . -maxdepth 1 -name "database_backup.sql.gz" -exec mv {} "$BACKUP_DIR/" \; 2>/dev/null || true

# Один .tar.gz со всем содержимым папки — внутри самой папки (удобно хранить/переносить)
(cd "$BACKUP_DIR" && tar -czf archive.tar.gz --exclude='archive.tar.gz' . 2>/dev/null) && echo "   ✅ archive.tar.gz создан в папке" || true
FINAL_ARCHIVE="$BACKUP_DIR/archive.tar.gz"
FINAL_SIZE=""
[ -f "$FINAL_ARCHIVE" ] && FINAL_SIZE=$(ls -lh "$FINAL_ARCHIVE" | awk '{print $5}')

# 5. Очистка только временных файлов в корне проекта (папку бэкапа не трогаем)
echo ""
echo "🧹 ШАГ 5: Очистка временных файлов в корне..."
find . -maxdepth 1 -name "storage_backup_*.tar.gz" -delete 2>/dev/null || true
find . -maxdepth 1 -name "database_backup.sql.gz" -delete 2>/dev/null || true

echo ""
echo "🎉 ПОЛНЫЙ БЭКАП ЗАВЕРШЕН!"
echo "====================================="
echo "📁 Папка бэкапа: $BACKUP_DIR"
echo "   (удали папку целиком, если этот бэкап не нужен)"
[ -n "$FINAL_SIZE" ] && echo "📦 Внутри: archive.tar.gz ($FINAL_SIZE)"
echo "📅 Дата: $(date)"
echo ""
echo "✅ Содержимое:"
[ -f "$BACKUP_DIR/database.sql.gz" ] && echo "   • База данных PostgreSQL ✓" || echo "   ⚠️ БАЗА ДАННЫХ ОТСУТСТВУЕТ"
echo "   • Код, миграции, env, Vercel, Auth-чеклист, Storage"
echo ""
echo "💡 Восстановление: ./restore_all.sh $BACKUP_NAME  (или укажи путь к папке)"
echo ""
echo "🚀 ГОТОВО! Нажмите любую клавишу для выхода..."
read -n 1 -s