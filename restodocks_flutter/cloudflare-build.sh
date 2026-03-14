#!/usr/bin/env bash
set -e
# Cloudflare Pages build для Flutter web.
# Требует env: SUPABASE_URL, SUPABASE_ANON_KEY (или NEXT_PUBLIC_*)

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  if [ -n "${NEXT_PUBLIC_SUPABASE_URL:-}" ] && [ -n "${NEXT_PUBLIC_SUPABASE_ANON_KEY:-}" ]; then
    export SUPABASE_URL="$NEXT_PUBLIC_SUPABASE_URL"
    export SUPABASE_ANON_KEY="$NEXT_PUBLIC_SUPABASE_ANON_KEY"
  else
    echo "ERROR: Set SUPABASE_URL and SUPABASE_ANON_KEY in Cloudflare Variables (Production + Preview)"
    exit 2
  fi
fi

SUPABASE_URL=$(echo "$SUPABASE_URL" | tr -d '\n\r\t' | sed 's/supabase\.con/supabase.co/')
SUPABASE_ANON_KEY=$(echo "$SUPABASE_ANON_KEY" | tr -d '\n\r\t')

echo "==> BUILD SUPABASE_URL=${SUPABASE_URL}"

echo "==> Installing Flutter 3.38.7..."
FLUTTER_DIR=".flutter"
rm -rf "$FLUTTER_DIR"
git clone --depth 1 -b 3.38.7 https://github.com/flutter/flutter.git "$FLUTTER_DIR"
export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"
flutter config --no-analytics --no-version-check
flutter --version

echo "==> flutter pub get"
flutter pub get

echo "==> Generating PWA icons"
dart run flutter_launcher_icons

echo "==> flutter build web (--no-web-resources-cdn, with source maps to avoid 404 parse error)"
ENABLE_TTK="${ENABLE_TTK_IMPORT:-false}"
flutter build web --release --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=ENABLE_TTK_IMPORT="$ENABLE_TTK"

if [ -f scripts/sw_cleanup.js ]; then
  cp scripts/sw_cleanup.js build/web/flutter_service_worker.js
fi

# Flutter.js ссылается на flutter.js.map, но Flutter его не генерирует → 404 и JSON Parse error в DevTools.
# Пустой source map убирает красную ошибку при показе проекта.
echo '{"version":3,"sources":[],"names":[],"mappings":""}' > build/web/flutter.js.map

echo "/*    /index.html   200" > build/web/_redirects

# Pages Functions: только /supabase-auth/* — остальное статика
cat > build/web/_routes.json << 'EOF'
{"version":1,"include":["/supabase-auth/*"],"exclude":[]}
EOF

cat > build/web/_headers << 'EOF'
/index.html
  Cache-Control: no-cache, no-store, must-revalidate

/*.js
  Cache-Control: public, max-age=31536000, immutable

/*.wasm
  Cache-Control: public, max-age=31536000, immutable
EOF

echo "==> Build OK: build/web"
