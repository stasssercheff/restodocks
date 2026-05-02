#!/usr/bin/env bash
# Сборка IPA для загрузки в App Store Connect → TestFlight.
# На Mac должны быть установлены сертификаты Apple Distribution и профиль для Runner (Xcode открывался хотя бы раз).
#
# Явный --export-options-plist нужен, чтобы шаг export (IPA из .xcarchive) не падал с ошибкой
# вроде «exportArchive … none were found» из‑за разных настроек Xcode/подписи; без plist иногда срабатывает, иногда нет.
set -euo pipefail
cd "$(dirname "$0")"
flutter pub get
# Символы для flutter symbolize при крашах — храните копию каталога вне build/ после сборки.
OBF_SYM_DIR="$(pwd)/build/obfuscation_symbols/ios_ipa"
mkdir -p "$OBF_SYM_DIR"
flutter build ipa --release --export-options-plist=ios/ExportOptions-appstore.plist \
  --obfuscate \
  --split-debug-info="$OBF_SYM_DIR"
IPA="build/ios/ipa/restodocks.ipa"
echo ""
echo "Готово: $(pwd)/$IPA"
echo "Символы обфускации (для symbolize / расследование крашей): $OBF_SYM_DIR"
echo ""
echo "Дальше:"
echo "  1) App Store Connect → «Мои приложения» → приложение с Bundle ID com.stassser.restodocks.dev.srebrikov"
echo "     (если ещё нет — создайте новое iOS-приложение с этим ID)."
echo "  2) Загрузите IPA: приложение «Transporter» (Mac App Store) или Xcode → Window → Organizer → Distribute."
echo "  3) В TestFlight дождитесь обработки (10–30 мин), добавьте тестеров."
echo ""
