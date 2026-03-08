#!/usr/bin/env bash
# Деплой Admin в Cloudflare Workers (после сборки)
# Запуск из корня репо — Path должен быть пустым
set -e
cd "$(dirname "$0")/admin" || exit 1
npx wrangler deploy
