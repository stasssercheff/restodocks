#!/bin/bash
set -e

# Быстрое восстановление из последнего бэкапа

echo "🚀 БЫСТРОЕ ВОССТАНОВЛЕНИЕ ИЗ ПОСЛЕДНЕГО БЭКАПА"
echo "==============================================="

# Находим последний архив
LATEST_BACKUP=$(ls -t *COMPLETE.tar.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ Архивы бэкапов не найдены!"
    exit 1
fi

echo "📦 ПОСЛЕДНИЙ АРХИВ: $LATEST_BACKUP"
echo "📅 ДАТА: $(date -r "$LATEST_BACKUP" '+%Y-%m-%d %H:%M:%S')"
echo "📊 РАЗМЕР: $(ls -lh "$LATEST_BACKUP" | awk '{print $5}')"
echo ""

read -p "✅ Восстановить из этого архива? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Отменено."
    exit 1
fi

echo "🔄 Запускаю восстановление..."
./restore_from_backup.sh "$LATEST_BACKUP"

echo ""
echo "🎉 ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО!"
echo "📁 Проверьте директорию restored_* для восстановленных файлов"