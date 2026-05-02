#!/usr/bin/env bash
# macOS → App Store Connect → TestFlight (не iOS / не IPA).
# Для Mac App Store нужен App Sandbox — отдельный файл entitlements в репозитории.
set -euo pipefail
cd "$(dirname "$0")"
flutter pub get
OBF_SYM_DIR="$(pwd)/build/obfuscation_symbols/macos"
mkdir -p "$OBF_SYM_DIR"
flutter build macos --release \
  --obfuscate \
  --split-debug-info="$OBF_SYM_DIR"
echo ""
echo "Символы обфускации: $OBF_SYM_DIR (сохраните для symbolize)"
echo ""
echo "=== TestFlight для macOS (не iPhone) ==="
echo ""
echo "1) В Xcode: open macos/Runner.xcworkspace"
echo ""
echo "2) Target «Runner» → Build Settings → в поиске: signing entitlements"
echo "    Для конфигурации «Release» укажите:"
echo "      Runner/Release-AppStore.entitlements"
echo "    (в нём включены Sandbox + сеть — требование магазина.)"
echo "    Для сборки DMG вне магазина верните обратно: Runner/Release.entitlements"
echo ""
echo "3) Схема «Runner» → Product → Archive → Distribute App → App Store Connect → Upload."
echo ""
echo "4) App Store Connect: приложение macOS с Bundle ID"
echo "     com.stassser.restodocks.dev.restodocks"
echo "   → раздел TestFlight."
echo ""
echo "Раньше упоминался iOS/IPA — это другой таргет; для десктопа только шаги выше."
echo ""
