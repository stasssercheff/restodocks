#!/usr/bin/env bash
# Сборка release и DMG на рабочий стол (двойной клик: chmod +x или запуск из терминала).
set -euo pipefail
cd "$(dirname "$0")"
flutter build macos --release
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R build/macos/Build/Products/Release/restodocks.app "$STAGING/"
ln -sf /Applications "$STAGING/Applications"
OUT="${HOME}/Desktop/Restodocks.dmg"
rm -f "$OUT"
hdiutil create -volname "Restodocks" -srcfolder "$STAGING" -ov -format UDZO "$OUT"
echo "OK: $OUT"
ls -la "$OUT"
echo ""
echo "Для раздачи другим Mac без предупреждения «повреждено»: подпись Developer ID + нотаризация."
echo "См. restodocks_flutter/scripts/macos-notarize-dmg.sh (нужен Apple Developer Program, ~99 USD/год)."
