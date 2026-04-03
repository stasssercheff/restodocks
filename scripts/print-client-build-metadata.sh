#!/usr/bin/env bash
# Печать метаданных для сопоставления билда приложения/клиента с коммитом Git.
# Не трогает деплой и сайт — только локальный вывод.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Client build metadata (run from repo root) ==="
echo "Date (local): $(date -Iseconds 2>/dev/null || date)"
echo "Git branch:   $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
echo "Git short:    $(git rev-parse --short HEAD 2>/dev/null || echo "?")"
echo "Git full:     $(git rev-parse HEAD 2>/dev/null || echo "?")"
echo "Last commit:  $(git log -1 --format='%ci %s' 2>/dev/null || echo "?")"
if [[ -f restodocks_flutter/pubspec.yaml ]]; then
  echo "pubspec:      $(grep -m1 '^version:' restodocks_flutter/pubspec.yaml | sed 's/^[[:space:]]*//')"
else
  echo "pubspec:      (restodocks_flutter/pubspec.yaml not found)"
fi
echo "=================================================="
