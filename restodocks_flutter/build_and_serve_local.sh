#!/bin/bash
# Сборка как в продакшене + локальный serve.
# То, что работает здесь — будет работать и на сайте после деплоя.

set -e
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

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "Создай restodocks_flutter/.env.local с:"
  echo "  SUPABASE_URL=...  (те же значения, что в Cloudflare → Environment Variables)"
  echo "  SUPABASE_ANON_KEY=..."
  exit 1
fi

SUPABASE_URL=$(echo "$SUPABASE_URL" | tr -d '\n\r\t' | sed 's/supabase\.con/supabase.co/')
SUPABASE_ANON_KEY=$(echo "$SUPABASE_ANON_KEY" | tr -d '\n\r\t')

echo "==> flutter clean"
flutter clean
echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web (--no-web-resources-cdn: CanvasKit в билде, без CDN)"
if ! flutter build web --profile --source-maps --no-tree-shake-icons --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"; then
  echo "==> Profile не прошёл, пробуем release..."
  flutter build web --release --no-web-resources-cdn \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
fi

if [ -f scripts/sw_cleanup.js ]; then
  cp scripts/sw_cleanup.js build/web/flutter_service_worker.js
fi

echo ""
echo "==> Сборка готова. Запуск сервера: http://localhost:8080"
echo "    Открой в браузере и проверь — это тот же билд, что попадёт на сайт."
echo ""

cd build/web && python3 -m http.server 8080
