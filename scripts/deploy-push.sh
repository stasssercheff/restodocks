#!/bin/bash
# Коммит и push для автодеплоя. Запускается после изменений в коде.
set -e
cd "$(dirname "$0")/.."
if [[ -n $(git status -s) ]]; then
  git add -A
  git commit -m "Update: $(date '+%Y-%m-%d %H:%M')"
  git push
  echo "✓ Push выполнен. Деплой запустится автоматически."
else
  echo "Нет изменений для коммита."
fi
