#!/bin/bash
set -e

# Полное восстановление Restodocks — код, БД, конфиг
# Использование:
#   ./restore_all.sh [архив_бэкапа]
#   ./restore_all.sh                    # из последнего архива
#   ./restore_all.sh --checkpoint       # только откат кода на checkpoint-working-20260225

echo "🔄 ВОССТАНОВЛЕНИЕ RESTODOCKS — ВСЁ ВОЗВРАЩАЕТСЯ"
echo "================================================="

# Режим только откат кода
if [ "$1" = "--checkpoint" ]; then
    echo ""
    echo "📌 ОТКАТ КОДА НА CHECKPOINT (20260225)"
    if git rev-parse checkpoint-working-20260225 >/dev/null 2>&1; then
        read -p "Откатить репозиторий на checkpoint-working-20260225? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git reset --hard checkpoint-working-20260225
            echo "✅ Код откатан на checkpoint-working-20260225"
        else
            echo "Отменено."
        fi
    else
        echo "❌ Тег checkpoint-working-20260225 не найден. Создайте: git tag checkpoint-working-20260225"
        exit 1
    fi
    exit 0
fi

# Режим полного восстановления из архива
BACKUP_ARCHIVE="${1:-}"

if [ -z "$BACKUP_ARCHIVE" ]; then
    LATEST=$(ls -t backups/backup_*.tar.gz *COMPLETE.tar.gz 2>/dev/null | head -1)
    if [ -z "$LATEST" ]; then
        echo "❌ Архивы бэкапа не найдены (backups/backup_*.tar.gz или *COMPLETE.tar.gz)"
        echo ""
        echo "💡 ИСПОЛЬЗОВАНИЕ:"
        echo "   ./restore_all.sh backups/backup_20260320_HHMMSS.tar.gz"
        echo "   ./restore_all.sh  # из последнего архива"
        echo "   ./restore_all.sh --checkpoint  # откат кода на checkpoint"
        exit 1
    fi
    BACKUP_ARCHIVE="$LATEST"
    echo "📦 Использую последний архив: $BACKUP_ARCHIVE"
fi

if [ ! -f "$BACKUP_ARCHIVE" ]; then
    echo "❌ Архив '$BACKUP_ARCHIVE' не найден!"
    exit 1
fi

echo "📦 АРХИВ: $BACKUP_ARCHIVE"
echo ""

# Временная директория
RESTORE_TMP=".restore_tmp_$$"
mkdir -p "$RESTORE_TMP"
trap "rm -rf $RESTORE_TMP" EXIT

echo "📦 ШАГ 1: Распаковка архива..."
tar -xzf "$BACKUP_ARCHIVE" -C "$RESTORE_TMP"
EXTRACTED=$(find "$RESTORE_TMP" -maxdepth 1 -type d ! -path "$RESTORE_TMP" | head -1)
if [ -z "$EXTRACTED" ]; then
    echo "❌ Не удалось найти распакованную папку"
    exit 1
fi
echo "   ✅ Распаковано"
echo ""

echo "📦 ШАГ 2: Восстановление кода..."
if [ -d "$EXTRACTED/code" ]; then
    if [ -L "supabase/functions" ] 2>/dev/null; then
        rm -f supabase/functions && mkdir -p supabase/functions
    fi
    rsync -a --exclude='.git' "$EXTRACTED/code/" ./ 2>/dev/null || cp -r "$EXTRACTED/code/"* ./
    echo "   ✅ Код восстановлен"
else
    echo "   ⚠️ Папка code не найдена в архиве"
fi
echo ""

echo "⚙️ ШАГ 3: Восстановление конфигурации..."
if [ -f "$EXTRACTED/environment.env" ]; then
    cp "$EXTRACTED/environment.env" .env
    echo "   ✅ .env восстановлен"
fi
if [ -f "$EXTRACTED/backup_config.env" ]; then
    cp "$EXTRACTED/backup_config.env" ./
    echo "   ✅ backup_config.env восстановлен (для restore БД)"
fi
if [ -d "$EXTRACTED/supabase_config" ]; then
    mkdir -p restodocks_flutter/supabase/migrations restodocks_flutter/supabase/functions
    cp -r "$EXTRACTED/supabase_config/migrations/"* restodocks_flutter/supabase/migrations/ 2>/dev/null || true
    cp -r "$EXTRACTED/supabase_config/functions/"* restodocks_flutter/supabase/functions/ 2>/dev/null || true
    echo "   ✅ Supabase конфигурация восстановлена"
fi
echo ""

echo "🗄️ ШАГ 4: Восстановление базы данных..."
if [ -f "$EXTRACTED/database.sql.gz" ]; then
    echo "   Найден дамп: database.sql.gz"
    cp "$EXTRACTED/database.sql.gz" ./
    if [ -f "backup_config.env" ]; then
        source backup_config.env 2>/dev/null || true
        if [ -n "$SUPABASE_DB_URL" ] && [[ "$SUPABASE_DB_URL" != *"YOUR_DB_PASSWORD"* ]]; then
            read -p "   Восстановить БД из дампа? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if command -v psql >/dev/null 2>&1; then
                    gunzip -c database.sql.gz | psql "$SUPABASE_DB_URL" 2>/dev/null && echo "   ✅ БД восстановлена" || echo "   ⚠️ Ошибка psql (проверьте backup_config.env)"
                else
                    echo "   ⚠️ psql не найден. Распакуйте вручную: gunzip database.sql.gz"
                    echo "   Затем: psql \"\$SUPABASE_DB_URL\" < database.sql"
                fi
            fi
        else
            echo "   ⚠️ Настройте backup_config.env (SUPABASE_DB_URL) и выполните: ./restore_database.sh"
        fi
    else
        echo "   ⚠️ backup_config.env не найден. Восстановите БД вручную: gunzip -c database.sql.gz | psql \"\$SUPABASE_DB_URL\""
    fi
else
    echo "   ⚠️ Дамп БД не найден в архиве (включите pg_dump в бэкап)"
fi
echo ""

echo "📋 ШАГ 5: Дополнительно (при необходимости)"
echo "   • Vercel env: см. vercel_env.env в архиве или Vercel Dashboard"
echo "   • Supabase Auth: см. SUPABASE_AUTH_CHECKLIST.md в архиве"
echo "   • Storage: если есть storage_backup — загрузите через Supabase CLI"
echo ""

echo "=========================================="
echo "✅ ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО"
echo ""
echo "🎯 ДАЛЬНЕЙШИЕ ШАГИ:"
echo "   1. flutter pub get && npm install"
echo "   2. Проверьте .env и backup_config.env"
echo "   3. При проблемах входа: scripts/fix_login_diagnostic.sql"
echo "   4. Deploy: git push (Vercel автодеплой)"
echo ""
echo "💡 Быстрый откат только кода: ./restore_all.sh --checkpoint"
echo ""
