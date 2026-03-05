#!/usr/bin/env bash
set -e
# Cloudflare Pages build для Flutter web.
# Требует env: SUPABASE_URL, SUPABASE_ANON_KEY (или NEXT_PUBLIC_*)
# Задайте в каждом проекте Cloudflare свои переменные: Production для основного, Staging для beta.

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  if [ -n "${NEXT_PUBLIC_SUPABASE_URL:-}" ] && [ -n "${NEXT_PUBLIC_SUPABASE_ANON_KEY:-}" ]; then
    export SUPABASE_URL="$NEXT_PUBLIC_SUPABASE_URL"
    export SUPABASE_ANON_KEY="$NEXT_PUBLIC_SUPABASE_ANON_KEY"
  else
    echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set in Cloudflare Pages Environment variables"
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

echo "==> flutter build web"
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

if [ -f scripts/sw_cleanup.js ]; then
  cp scripts/sw_cleanup.js build/web/flutter_service_worker.js
fi

echo "/*    /index.html   200" > build/web/_redirects

echo "==> Build OK: build/web"
