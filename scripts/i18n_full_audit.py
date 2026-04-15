#!/usr/bin/env python3
"""Обёртка: запуск из корня репозитория Restodocks → реальный скрипт в restodocks_flutter/scripts/."""
from __future__ import annotations

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_HERE)
_TARGET = os.path.join(_REPO, "restodocks_flutter", "scripts", "i18n_full_audit.py")

if not os.path.isfile(_TARGET):
    print(f"Не найден: {_TARGET}", file=sys.stderr)
    sys.exit(1)

os.chdir(os.path.join(_REPO, "restodocks_flutter"))
os.execv(sys.executable, [sys.executable, _TARGET] + sys.argv[1:])
