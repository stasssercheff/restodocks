#!/usr/bin/env bash
set -e
# Production: используем ту же Supabase, что и Beta (одна БД для обоих).
# Задайте SUPABASE_URL и SUPABASE_ANON_KEY в Cloudflare Prod Variables — те же, что у Beta.

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  if [ -n "${NEXT_PUBLIC_SUPABASE_URL:-}" ] && [ -n "${NEXT_PUBLIC_SUPABASE_ANON_KEY:-}" ]; then
    export SUPABASE_URL="$NEXT_PUBLIC_SUPABASE_URL"
    export SUPABASE_ANON_KEY="$NEXT_PUBLIC_SUPABASE_ANON_KEY"
  else
    echo "ERROR: Set SUPABASE_URL and SUPABASE_ANON_KEY in Cloudflare Prod Variables (скопируй из Beta — одна БД)"
    exit 2
  fi
fi

SUPABASE_URL=$(echo "$SUPABASE_URL" | tr -d '\n\r\t' | sed 's/supabase\.con/supabase.co/')
SUPABASE_ANON_KEY=$(echo "$SUPABASE_ANON_KEY" | tr -d '\n\r\t')

echo "==> Production build: SUPABASE_URL=${SUPABASE_URL}"

echo "==> Installing Flutter 3.38.7..."
FLUTTER_DIR=".flutter"
rm -rf "$FLUTTER_DIR"
git clone --depth 1 -b 3.38.7 https://github.com/flutter/flutter.git "$FLUTTER_DIR"
export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"
flutter config --no-analytics --no-version-check
flutter --version

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web (--no-web-resources-cdn)"
flutter build web --release --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

if [ -f scripts/sw_cleanup.js ]; then
  cp scripts/sw_cleanup.js build/web/flutter_service_worker.js
fi

echo "/*    /index.html   200" > build/web/_redirects

cat > build/web/_headers << 'EOF'
/index.html
  Cache-Control: no-cache, no-store, must-revalidate

/*.js
  Cache-Control: public, max-age=31536000, immutable

/*.wasm
  Cache-Control: public, max-age=31536000, immutable
EOF

echo "==> Build OK: build/web"
