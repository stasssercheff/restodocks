#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# npx (Supabase CLI) — добавляем node в PATH если нужно
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"

echo "🚀 ЗАПУСК ПОЛНОГО БЭКАПА RESTODOCKS"
echo "====================================="
echo "Дата: $(date)"
echo ""

# Supabase CLI используется для дампа БД — pg_dump не нужен
if ! command -v npx >/dev/null 2>&1; then
    echo "❌ ОШИБКА: npx (Node.js) не найден"
    echo "   Установи Node.js: https://nodejs.org"
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

# 2. БЭКАП БАЗЫ ДАННЫХ через pg_dump + Supabase Session Pooler
# (Supabase закрыл прямой порт 5432 на db.*, используем pooler: aws-1-ap-south-1.pooler.supabase.com)
echo ""
echo "🗄️ ШАГ 2: Бэкап базы данных..."
[ -f backup_config.env ] && source backup_config.env 2>/dev/null || true

# Строим pooler URL из пароля (пароль берём из SUPABASE_DB_URL)
DB_PASSWORD=""
if [ -n "$SUPABASE_DB_URL" ]; then
    # Извлекаем пароль из URL вида: postgresql://postgres:PASSWORD@host...
    DB_PASSWORD=$(echo "$SUPABASE_DB_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
fi

if [ -z "$DB_PASSWORD" ]; then
    echo "   ⚠️ Пароль БД не найден в backup_config.env"
    echo "      Добавь: SUPABASE_DB_URL=postgresql://postgres:ПАРОЛЬ@db.osglfptwbuqqmqunttha.supabase.co:5432/postgres"
    echo "      Пароль в Supabase Dashboard → Project Settings → Database → Database password"
else
    POOLER_URL="postgresql://postgres.osglfptwbuqqmqunttha:${DB_PASSWORD}@aws-1-ap-south-1.pooler.supabase.com:6543/postgres?sslmode=require"
    if pg_dump "$POOLER_URL" --no-owner --no-privileges --clean --if-exists \
        -f "$BACKUP_DIR/database.sql" 2>"$BACKUP_DIR/db_dump_err.txt"; then
        if [ -s "$BACKUP_DIR/database.sql" ]; then
            gzip "$BACKUP_DIR/database.sql"
            echo "   ✅ База данных сохранена: database.sql.gz"
        else
            echo "   ⚠️ database.sql пустой — возможно ошибка подключения"
            [ -s "$BACKUP_DIR/db_dump_err.txt" ] && cat "$BACKUP_DIR/db_dump_err.txt"
        fi
    else
        echo "   ⚠️ Ошибка pg_dump:"
        [ -s "$BACKUP_DIR/db_dump_err.txt" ] && cat "$BACKUP_DIR/db_dump_err.txt"
        echo "      Проверь пароль БД в Supabase Dashboard → Project Settings → Database → Reset password"
    fi
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
    [ -f backup_config.env ] && source backup_config.env 2>/dev/null || true
    if [ -z "$SUPABASE_SERVICE_ROLE_KEY" ] || [ "$SUPABASE_SERVICE_ROLE_KEY" = "YOUR_SERVICE_ROLE_KEY_HERE" ]; then
        echo "   ⚠️ SUPABASE_SERVICE_ROLE_KEY не задан в backup_config.env — storage пропущен"
        echo "      Получи ключ: Supabase Dashboard → Project Settings → API → service_role"
    else
        echo "   Запускаю бэкап storage..."
        STORAGE_BACKUP_DIR="$BACKUP_DIR/storage_backup" \
        SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co \
        SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
        python3 storage_backup.py && echo "   ✅ Storage сохранён в $BACKUP_DIR/storage_backup" || echo "   ⚠️ Ошибка бэкапа storage"
        # Удаляем лишний .tar.gz который создаёт скрипт — данные уже в нужной папке
        find . -maxdepth 1 -name "storage_backup_*.tar.gz" -delete 2>/dev/null || true
    fi
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
[ -f "$BACKUP_DIR/database.sql.gz" ] && echo "   • База данных PostgreSQL ✓" || echo "   ⚠️ БАЗА ДАННЫХ ОТСУТСТВУЕТ — проверьте supabase login"
echo "   • Код, миграции, env, Vercel, Auth-чеклист"
[ -d "$BACKUP_DIR/storage_backup" ] && echo "   • Storage ✓" || echo "   ⚠️ Storage не сохранён — добавьте SUPABASE_SERVICE_ROLE_KEY в backup_config.env"
echo ""
echo "💡 Восстановление: ./restore_all.sh $BACKUP_NAME  (или укажи путь к папке)"
echo ""
echo "🚀 ГОТОВО!"
# read -n 1 -s  # отключено для неинтерактивного запуска