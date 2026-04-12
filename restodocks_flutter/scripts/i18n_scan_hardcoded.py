#!/usr/bin/env python3
"""
Поиск подозрительных захардкоженных строк UI в Dart (не через loc.t / ключи).

Исключает: *.g.dart, generated, тесты *_test.dart, строки с интерполяцией $,
очевидные техстроки (http, asset, package:).

Запуск из restodocks_flutter:
  python3 scripts/i18n_scan_hardcoded.py
  python3 scripts/i18n_scan_hardcoded.py --json

Выход: список file:line и фрагмент строки — для ручной замены на loc.t('key').
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"

SKIP_NAME = re.compile(
    r"\.g\.dart$|_test\.dart$|\.freezed\.dart$|\.mocks\.dart$",
    re.I,
)

# Уже локализовано или не UI
SKIP_LINE = re.compile(
    r"loc\.t\(|LocalizationService|\b_t\(|"
    r"devLog\(|debugPrint\(|print\(|"
    r"import\s+|package:|assets/|http[s]?://|"
    r"RegExp\(|r['\"]|Color\(0x|Icons\.|FontWeight|"
    r"Locale\(|MaterialApp|Route",
)

# Text( '...' ) — основной случай; labelText: через отдельный паттерн
TEXT_SIMPLE = re.compile(r"\bText\s*\(\s*['\"]([^'\"]{2,})['\"]")
LABEL_HINT = re.compile(
    r"(?:labelText|hintText|helperText|semanticLabel|tooltip)\s*:\s*['\"]([^'\"]{2,})['\"]",
    re.I,
)
SNACK = re.compile(r"SnackBar\s*\(\s*(?:[^)]*\b)?content\s*:\s*Text\s*\(\s*['\"]([^'\"]{2,})['\"]", re.I)
# Минимум букв (латиница/кириллица)
def looks_ui(s: str) -> bool:
    s = s.strip()
    if len(s) < 3:
        return False
    if not re.search(r"[A-Za-z\u0400-\u04FF]", s):
        return False
    low = s.lower()
    if low in {"true", "false", "null", "void", "int", "double", "string"}:
        return False
    return True


def scan_file(path: Path) -> list[tuple[int, str, str]]:
    out: list[tuple[int, str, str]] = []
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return out
    for i, line in enumerate(text.splitlines(), 1):
        if SKIP_LINE.search(line):
            continue
        if "loc.t(" in line or "_t(" in line:
            continue
        # Простая эвристика: кавычки с текстом в UI-контексте
        for rx in (TEXT_SIMPLE, LABEL_HINT, SNACK):
            for m in rx.finditer(line):
                frag = m.group(1)
                if "${" in frag or frag.startswith("$"):
                    continue
                if looks_ui(frag):
                    if re.match(r"^[a-z0-9.\-]+\.[a-z]{2,}$", frag, re.I):
                        continue
                    out.append((i, line.strip(), frag))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    hits: list[dict[str, str | int]] = []
    for path in sorted(LIB.rglob("*.dart")):
        if SKIP_NAME.search(path.name):
            continue
        rel = path.relative_to(ROOT)
        for line_no, line, frag in scan_file(path):
            hits.append(
                {
                    "file": str(rel),
                    "line": line_no,
                    "fragment": frag,
                    "context": line[:240],
                }
            )

    if args.json:
        json.dump(hits, sys.stdout, ensure_ascii=False, indent=2)
        print()
    else:
        print(f"Подозрительных вхождений: {len(hits)} (эвристика, нужна ручная проверка)\n")
        for h in hits[:200]:
            print(f"{h['file']}:{h['line']}\n  [{h['fragment']!r}]\n  {h['context']}\n")
        if len(hits) > 200:
            print(f"... ещё {len(hits) - 200} строк; полный список: --json")


if __name__ == "__main__":
    main()
