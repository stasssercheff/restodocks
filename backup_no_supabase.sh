#!/bin/bash
set -euo pipefail

# МЕГАБЭКАП БЕЗ SUPABASE (БД/Storage)
# Supabase сама архивирует данные каждые 24 часа, поэтому здесь сохраняем только:
# - код проекта (как есть, включая локальные файлы)
# - миграции и supabase functions (то, что хранится в репозитории)
# - env/vercel конфиги и чеклисты
#
# Результат: папка в backups/ и archive.tar.gz внутри неё.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 МЕГАБЭКАП (без Supabase БД/Storage)"
echo "====================================="
echo "Дата: $(date)"
echo ""

BACKUPS_ROOT="backups"
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)_no_supabase"
BACKUP_DIR="$BACKUPS_ROOT/$BACKUP_NAME"
mkdir -p "$BACKUP_DIR"

echo "📁 Папка бэкапа: $BACKUP_DIR"
echo ""

# 1) Код + конфиги (включая supabase_config из репозитория)
echo "📦 ШАГ 1: Бэкап кода и конфигурации..."
export BACKUP_TARGET_DIR="$BACKUP_DIR"
if [ ! -f "./full_backup.sh" ]; then
  echo "❌ Не найден ./full_backup.sh. Запустите скрипт из корня репозитория."
  exit 1
fi
chmod +x ./full_backup.sh 2>/dev/null || true
./full_backup.sh > /dev/null 2>&1
echo "   ✅ Код и конфигурация сохранены"

# 2) Extras (Vercel env + auth checklist)
echo ""
echo "📋 ШАГ 2: Extras (Vercel env, Auth чеклист)..."
if [ -f "scripts/backup_extras.sh" ]; then
  chmod +x scripts/backup_extras.sh 2>/dev/null || true
  ./scripts/backup_extras.sh "$BACKUP_DIR" 2>/dev/null || true
fi

# 3) Финальный архив внутри папки
echo ""
echo "📦 ШАГ 3: Архив внутри папки бэкапа..."
(cd "$BACKUP_DIR" && tar -czf archive.tar.gz --exclude='archive.tar.gz' . 2>/dev/null) && \
  echo "   ✅ archive.tar.gz создан" || true

FINAL_ARCHIVE="$BACKUP_DIR/archive.tar.gz"
FINAL_SIZE=""
[ -f "$FINAL_ARCHIVE" ] && FINAL_SIZE=$(ls -lh "$FINAL_ARCHIVE" | awk '{print $5}')

echo ""
echo "🎉 МЕГАБЭКАП ЗАВЕРШЕН!"
echo "====================================="
echo "📁 Папка бэкапа: $BACKUP_DIR"
[ -n "$FINAL_SIZE" ] && echo "📦 Внутри: archive.tar.gz ($FINAL_SIZE)"
echo "✅ Содержимое: код, миграции/functions в репо, env/vercel/auth чеклист"
echo ""
echo "🚀 ГОТОВО!"

