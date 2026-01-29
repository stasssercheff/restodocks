#!/usr/bin/env bash
# Запуск Flutter web в Safari (по умолчанию для локальной разработки).
# Использует web-server; после старта открой Safari → http://localhost:8080

set -e
cd "$(dirname "$0")"
echo "→ Запуск web-server на :8080. Открой Safari: http://localhost:8080"
exec flutter run -d web-server --web-port=8080
