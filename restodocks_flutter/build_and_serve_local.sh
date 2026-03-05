#!/bin/bash
# Сборка как в продакшене (Vercel) + локальный serve.
# То, что работает здесь — будет работать и на сайте после деплоя.

set -e
cd "$(dirname "$0")"

# Env из .env.local (те же ключи, что в Vercel/Netlify)
if [ -f .env.local ]; then
  set -a
  source .env.local
  set +a
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "Создай restodocks_flutter/.env.local с:"
  echo "  SUPABASE_URL=...  (те же значения, что в Vercel → Environment Variables)"
  echo "  SUPABASE_ANON_KEY=..."
  exit 1
fi

# Очистка env (как в vercel-build)
SUPABASE_URL=$(echo "$SUPABASE_URL" | tr -d '\n\r\t' | sed 's/supabase\.con/supabase.co/')
SUPABASE_ANON_KEY=$(echo "$SUPABASE_ANON_KEY" | tr -d '\n\r\t')

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web (как на Vercel: profile + source-maps)"
if ! flutter build web --profile --source-maps --no-tree-shake-icons \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"; then
  echo "==> Profile не прошёл, пробуем release..."
  flutter build web --release \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
fi

# Те же патчи, что в vercel-build.sh
echo "==> Патч service worker (как на Vercel)"
if [ -f scripts/sw_cleanup.js ]; then
  cp scripts/sw_cleanup.js build/web/flutter_service_worker.js
fi

echo "==> Патч bootstrap (отключение SW)"
if [ -f build/web/flutter_bootstrap.js ]; then
  python3 -c "
import re
p = 'build/web/flutter_bootstrap.js'
with open(p) as f: c = f.read()
c2 = re.sub(r'load\(\{\s*serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*\"[^\"]*\"\s*\}\s*\}\)', 'load({})', c)
if c != c2:
    with open(p, 'w') as f: f.write(c2)
    print('Bootstrap patched')
" 2>/dev/null || true
fi

echo ""
echo "==> Сборка готова. Запуск сервера: http://localhost:8080"
echo "    Открой в браузере и проверь — это тот же билд, что попадёт на сайт."
echo ""
cd build/web && python3 -m http.server 8080
