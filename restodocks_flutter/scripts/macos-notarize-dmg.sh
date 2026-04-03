#!/usr/bin/env bash
# =============================================================================
# Нотаризация DMG для раздачи другим Mac без «приложение повреждено» / xattr.
#
# Требуется (разово):
#   • Платная подписка Apple Developer Program (99 USD/год)
#   • Сертификат «Developer ID Application» в связке ключей (Xcode → Settings → Accounts)
#   • App-specific password для Apple ID: https://appleid.apple.com → Sign-In and Security
#
# Перед этим скриптом .app должен быть подписан Developer ID (не adhoc):
#   1) macos/Runner/Configs: cp Signing.xcconfig.example Signing.xcconfig
#      → DEVELOPMENT_TEAM = ваш_10_символьный_Team_ID
#   2) flutter build macos --release
#   3) Проверка: codesign -dv build/macos/Build/Products/Release/restodocks.app
#      → должно быть Authority=Developer ID Application: … (не Signature=adhoc)
#   4) ./package_macos_dmg.sh  → ~/Desktop/Restodocks.dmg
#
# Переменные окружения:
#   APPLE_ID          — Apple ID (email)
#   APPLE_TEAM_ID     — 10 символов Team ID (Membership в developer.apple.com)
#   NOTARY_PASSWORD   — app-specific password (не пароль от iCloud)
#
# Пример:
#   export APPLE_ID="you@mail.com"
#   export APPLE_TEAM_ID="XXXXXXXXXX"
#   export NOTARY_PASSWORD="abcd-efgh-ijkl-mnop"
#   ./scripts/macos-notarize-dmg.sh ~/Desktop/Restodocks.dmg
# =============================================================================
set -euo pipefail

DMG="${1:-${HOME}/Desktop/Restodocks.dmg}"

if [[ ! -f "$DMG" ]]; then
  echo "Файл не найден: $DMG"
  exit 1
fi

: "${APPLE_ID:?Задайте APPLE_ID}"
: "${APPLE_TEAM_ID:?Задайте APPLE_TEAM_ID}"
: "${NOTARY_PASSWORD:?Задайте NOTARY_PASSWORD (app-specific password)}"

echo "Отправка на нотаризацию: $DMG"
# --wait дождётся результата (несколько минут)
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait

echo "Прикрепление ticket (staple) к DMG…"
xcrun stapler staple "$DMG"

echo "Готово. Раздавайте этот DMG — Gatekeeper не должен ругаться на «повреждено»."
xcrun stapler validate "$DMG"
