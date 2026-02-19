#!/usr/bin/env bash
set -e

echo "==> Vercel Flutter build started"

# В GitHub Actions Flutter уже собран через flutter-action; vercel build только упаковывает.
if [ -n "$SKIP_FLUTTER_BUILD" ] && [ -f "build/web/index.html" ]; then
  echo "==> Skipping Flutter build (pre-built in CI); build/web ready"
  exit 0
fi

# Проверка env (Vercel передаёт их в build)
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "ERROR: SUPABASE_URL or SUPABASE_ANON_KEY not set. Set them in Vercel Project Settings → Environment Variables."
  exit 1
fi
echo "==> Env OK"

# Установка Flutter (Vercel не включает Flutter). Пин 3.38.7 (stable) для intl ^0.20.2.
# Удаляем кэш .flutter, чтобы не использовать старую версию.
FLUTTER_DIR=".flutter"
rm -rf "$FLUTTER_DIR"
echo "==> Installing Flutter 3.38.7..."
git clone --depth 1 -b 3.38.7 https://github.com/flutter/flutter.git "$FLUTTER_DIR" || { echo "ERROR: Flutter clone failed"; exit 1; }
export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"
flutter config --no-analytics --no-version-check
flutter --version || { echo "ERROR: Flutter version failed"; exit 1; }

echo "==> Writing config.json from env (with trim)"
python3 -c "
import os, json, re
def clean(s):
    if not s: return ''
    s = re.sub(r'[\n\r\t]', '', str(s).strip())
    s = s.replace('supabase.con', 'supabase.co')  # fix typo
    return s
url = clean(os.environ.get('SUPABASE_URL', ''))
key = clean(os.environ.get('SUPABASE_ANON_KEY', ''))
if not url or not key:
    print('WARNING: SUPABASE_URL or SUPABASE_ANON_KEY empty after trim, using fallback from repo')
    # Fallback: read existing config.json if present (repo has correct values)
    p = os.path.join('assets', 'config.json')
    if os.path.exists(p):
        with open(p) as f:
            existing = json.load(f)
        url = url or existing.get('SUPABASE_URL', '')
        key = key or existing.get('SUPABASE_ANON_KEY', '')
p = os.path.join('assets', 'config.json')
d = {'SUPABASE_URL': url, 'SUPABASE_ANON_KEY': key}
with open(p, 'w') as f:
    json.dump(d, f)
print('config.json written, URL len=%d, key len=%d' % (len(url), len(key)))
" || { echo "ERROR: config.json failed"; exit 1; }

echo "==> flutter clean"
flutter clean || true

echo "==> flutter pub get"
flutter pub get || { echo "ERROR: pub get failed"; exit 1; }

# Build for release with source maps
echo "==> flutter build web --profile --source-maps --no-tree-shake-icons"
flutter build web --profile --source-maps --no-tree-shake-icons 2>&1 | tee build.log
BUILD_EXIT=${PIPESTATUS[0]}

if [ "$BUILD_EXIT" -ne 0 ]; then
  echo "==> Profile build failed, trying release build without source maps..."
  echo "==> flutter build web --release --dart-define=FLUTTER_WEB_OBFUSCATE=true"
  flutter build web --release --dart-define=FLUTTER_WEB_OBFUSCATE=true 2>&1 | tee build.log
  BUILD_EXIT=${PIPESTATUS[0]}
fi
if [ "$BUILD_EXIT" -ne 0 ]; then
  echo "ERROR: flutter build web failed (exit $BUILD_EXIT). Last 120 lines of build.log:"
  tail -120 build.log
  exit 1
fi

if [ ! -f "build/web/index.html" ]; then
  echo "ERROR: build/web/index.html not found after build"
  exit 1
fi

# Проверяем, сгенерированы ли source maps
if [ ! -f "build/web/flutter.js.map" ]; then
  echo "WARNING: flutter.js.map not found - source maps may not be generated"
else
  echo "==> Source maps found: flutter.js.map"
fi

echo "==> Build OK: build/web ready"
echo "==> Deploy triggered at: $(date)"
echo "==> All fixes applied: inventory buttons, fixed columns, product loading"
