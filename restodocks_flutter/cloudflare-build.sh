#!/usr/bin/env bash
set -e
# Cloudflare Pages build для Flutter web.
# Prod: задайте DEPLOY_TARGET=production — будет использован Production Supabase.
# Beta/demo: SUPABASE_URL и SUPABASE_ANON_KEY (Staging) — без DEPLOY_TARGET.

PROD_URL="https://osglfptwbuqqmqunttha.supabase.co"
PROD_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE"

if [ "${DEPLOY_TARGET:-}" = "production" ]; then
  export SUPABASE_URL="$PROD_URL"
  export SUPABASE_ANON_KEY="$PROD_KEY"
  echo "==> DEPLOY_TARGET=production: using Production Supabase"
else
  if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
    if [ -n "${NEXT_PUBLIC_SUPABASE_URL:-}" ] && [ -n "${NEXT_PUBLIC_SUPABASE_ANON_KEY:-}" ]; then
      export SUPABASE_URL="$NEXT_PUBLIC_SUPABASE_URL"
      export SUPABASE_ANON_KEY="$NEXT_PUBLIC_SUPABASE_ANON_KEY"
    else
      echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set (or DEPLOY_TARGET=production)"
      exit 2
    fi
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
