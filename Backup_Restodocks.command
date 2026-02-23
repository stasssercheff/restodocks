#!/bin/bash
# Остаемся в директории скрипта (уже правильная директория)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Запуск полного бэкапа Restodocks..."
echo "======================================"
echo "Директория проекта: $SCRIPT_DIR"
echo ""

./backup_all.sh