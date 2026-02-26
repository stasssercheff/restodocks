#!/bin/bash
# Остаемся в директории скрипта (уже правильная директория)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Чтобы pg_dump находился при запуске двойным щелчком (терминал не грузит .zshrc)
[ -d "/Applications/Postgres.app/Contents/Versions/latest/bin" ] && export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"

echo "Запуск полного бэкапа Restodocks..."
echo "======================================"
echo "Директория проекта: $SCRIPT_DIR"
echo ""

./backup_all.sh