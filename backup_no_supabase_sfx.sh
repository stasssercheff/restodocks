#!/bin/bash
set -euo pipefail

# ОДИН ФАЙЛ БЭКАПА (Self-extracting) БЕЗ SUPABASE (БД/Storage)
#
# Результат: один файл в backups/ вида:
#   backup_YYYYMMDD_HHMMSS_no_supabase.command
#
# При двойном клике (macOS) файл сам распакует payload в папку рядом с собой
# и запустит восстановление через ВОССТАНОВИТЬ.sh.
#
# Примечание macOS: может потребоваться "Правый клик → Открыть" из-за Gatekeeper.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BACKUPS_ROOT="backups"
BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)_no_supabase"
WORK_DIR="$BACKUPS_ROOT/${BACKUP_NAME}_work"
OUT_FILE="$BACKUPS_ROOT/${BACKUP_NAME}.command"

mkdir -p "$WORK_DIR"

echo "🚀 МЕГАБЭКАП (один файл, без Supabase БД/Storage)"
echo "==============================================="
echo "Дата: $(date)"
echo "📁 Временная папка: $WORK_DIR"

# 1) Собираем содержимое (код/конфиги/экстры) в work-папку
export BACKUP_TARGET_DIR="$WORK_DIR"
./full_backup.sh > /dev/null 2>&1

if [ -f "scripts/backup_extras.sh" ]; then
  chmod +x scripts/backup_extras.sh 2>/dev/null || true
  ./scripts/backup_extras.sh "$WORK_DIR" 2>/dev/null || true
fi

# 2) Делаем tar.gz payload
PAYLOAD_TGZ="$WORK_DIR/payload.tar.gz"
(cd "$WORK_DIR" && tar -czf "payload.tar.gz" --exclude='payload.tar.gz' .)

# 3) Генерируем self-extracting .command (shell script + appended tar.gz)
cat > "$OUT_FILE" <<'SFXEOF'
#!/bin/bash
set -euo pipefail

echo "🔄 Restodocks: восстановление из self-extracting бэкапа"
echo "======================================================"

SELF="$0"
BASE_DIR="$(cd "$(dirname "$SELF")" && pwd)"

# Куда распаковывать (рядом с файлом)
TS="$(date +%Y%m%d_%H%M%S)"
DEST_DIR="$BASE_DIR/restored_from_backup_$TS"
mkdir -p "$DEST_DIR"

echo "📁 Распаковка в: $DEST_DIR"

# Находим строку-маркер и распаковываем всё, что ниже (это tar.gz)
MARK_LINE="$(grep -n '^__RESTODOCKS_BACKUP_PAYLOAD_BELOW__$' "$SELF" | cut -d: -f1 | tail -n 1)"
if [ -z "$MARK_LINE" ]; then
  echo "❌ Не найден payload marker в файле."
  exit 1
fi

PAYLOAD_START=$((MARK_LINE + 1))
tail -n +"$PAYLOAD_START" "$SELF" | tar -xzf - -C "$DEST_DIR"

echo "✅ Распаковка завершена"

if [ -f "$DEST_DIR/ВОССТАНОВИТЬ.sh" ]; then
  chmod +x "$DEST_DIR/ВОССТАНОВИТЬ.sh" 2>/dev/null || true
  echo "🚀 Запускаю восстановление..."
  (cd "$DEST_DIR" && ./ВОССТАНОВИТЬ.sh)
else
  echo "⚠️ Не найден ВОССТАНОВИТЬ.sh. Папка распакована: $DEST_DIR"
fi

exit 0

__RESTODOCKS_BACKUP_PAYLOAD_BELOW__
SFXEOF

# Append payload bytes after marker
cat "$PAYLOAD_TGZ" >> "$OUT_FILE"
chmod +x "$OUT_FILE"

SIZE="$(ls -lh "$OUT_FILE" | awk '{print $5}')"
echo ""
echo "🎉 ГОТОВО!"
echo "✅ Один файл создан: $OUT_FILE ($SIZE)"
echo "ℹ️ Можно переносить/хранить как единый файл."
echo "🧹 Временная папка work останется для проверки: $WORK_DIR"

