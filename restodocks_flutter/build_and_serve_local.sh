#!/bin/bash
# Сборка и локальный сервер — откройте http://localhost:8080 в Safari

cd "$(dirname "$0")"

if [ -f .env.local ]; then
  set -a
  source .env.local
  set +a
fi

SUPABASE_URL="${SUPABASE_URL:-https://osglfptwbuqqmqunttha.supabase.co}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

if [ -z "$SUPABASE_ANON_KEY" ] && [ -f assets/config.json ]; then
  SUPABASE_ANON_KEY=$(grep -o '"SUPABASE_ANON_KEY":"[^"]*"' assets/config.json | cut -d'"' -f4)
fi

echo "==> flutter clean"
flutter clean

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web"
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --no-web-resources-cdn

echo ""
echo "==> Запуск сервера на порту 8080"
echo "    Откройте в Safari: http://localhost:8080"
echo "    Ctrl+C — остановить"
echo ""

cd build/web && python3 -m http.server 8080
