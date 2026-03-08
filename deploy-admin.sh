#!/usr/bin/env bash
# Сборка Admin (Next.js → Cloudflare Workers)
# Запуск из корня репо — для Cloudflare Builds (Path должен быть пустым)
set -e
ADMIN_DIR="$(cd "$(dirname "$0")/admin" && pwd)"
cd "$ADMIN_DIR"
npm ci
npx opennextjs-cloudflare build
