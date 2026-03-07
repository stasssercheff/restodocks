#!/bin/bash
# Локальный запуск Restodocks Demo
# Для проверки «как на сайте» — используй ./build_and_serve_local.sh (собирает как Vercel)

cd "$(dirname "$0")"

# Создай .env.local с:
#   SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co
#   SUPABASE_ANON_KEY=eyJ... (из Supabase → Settings → API → anon public)
if [ -f .env.local ]; then
  set -a
  source .env.local
  set +a
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "Создай restodocks_flutter/.env.local с:"
  echo "  SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co"
  echo "  SUPABASE_ANON_KEY=<твой anon key из Supabase → Settings → API>"
  exit 1
fi

echo "==> flutter pub get"
flutter pub get

echo ""
echo "==> Запуск на web-server (откройте ссылку в Safari)"
echo "    SUPABASE_URL=$SUPABASE_URL"
echo ""
flutter run -d web-server \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
