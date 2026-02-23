#!/bin/bash

set -e

echo "=== Restodocks Desktop Setup ==="
echo "Это автоматическая установка Electron приложения"
echo ""

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js не установлен!"
    echo "📥 Скачайте и установите Node.js 18+ с https://nodejs.org"
    echo "После установки запустите этот скрипт снова."
    exit 1
fi

NODE_VERSION=$(node --version | sed 's/v//')
REQUIRED_VERSION="18.0.0"

if ! [ "$(printf '%s\n' "$REQUIRED_VERSION" "$NODE_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
    echo "❌ Node.js версии $NODE_VERSION недостаточно. Требуется 18+"
    exit 1
fi

echo "✅ Node.js $NODE_VERSION найден"
echo "✅ npm $(npm --version) найден"
echo ""

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter SDK не установлен!"
    echo "📥 Скачайте и установите Flutter с https://flutter.dev"
    echo "После установки запустите этот скрипт снова."
    exit 1
fi

echo "✅ Flutter $(flutter --version | head -1) найден"
echo ""

# Install npm dependencies
echo "📦 Установка зависимостей Electron..."
npm install

# Build Flutter web app
echo "🔨 Сборка Flutter веб-приложения..."
cd restodocks_flutter
flutter pub get
flutter build web --release --web-renderer canvaskit
cd ..

# Build Electron app
echo "🏗️ Сборка Electron приложения..."
npm run build-electron

echo ""
echo "🎉 Готово!"
echo "📁 Ваше приложение находится в папке 'dist/'"
echo ""
echo "🚀 Для запуска в режиме разработки:"
echo "   npm run build-web && NODE_ENV=development npm start"
echo ""
echo "📋 Для сборки только для вашей платформы:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "   npm run build-electron-mac    # для Mac"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    echo "   npm run build-electron-win    # для Windows"
else
    echo "   npm run build-electron        # для Linux"
fi