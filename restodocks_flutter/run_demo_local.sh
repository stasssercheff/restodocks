#!/bin/bash
# Локальный запуск Restodocks Demo — без деплоя в Vercel.
# Приложение подключается к тому же Supabase, что и restodocks-demo.vercel.app

cd "$(dirname "$0")"

echo "==> flutter pub get"
flutter pub get

echo ""
echo "==> Запуск на web-server (откройте ссылку в Safari)"
echo "    После старта откройте в браузере: http://localhost:PORT"
echo ""
flutter run -d web-server
