#!/usr/bin/env python3
"""
Отчёт по словарю localizable.json: сколько ключей совпадает с en (плейсхолдеры),
по каким языкам; опционально список ключей для выгрузки в перевод.

Запуск из корня репозитория:
  python3 restodocks_flutter/scripts/i18n_gap_report.py
  python3 restodocks_flutter/scripts/i18n_gap_report.py --lang kk --limit 80
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets" / "translations" / "localizable.json"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default=None, help="Только этот код языка (например kk)")
    ap.add_argument("--limit", type=int, default=50, help="Сколько примеров ключей показать")
    args = ap.parse_args()

    with JSON_PATH.open(encoding="utf-8") as f:
        data: dict[str, dict[str, str]] = json.load(f)

    en = data.get("en", {})
    langs = [args.lang] if args.lang else sorted(k for k in data if k != "en")

    for lang in langs:
        block = data.get(lang, {})
        same_as_en = [
            k
            for k in en
            if k in block and (block[k] or "").strip() == (en.get(k) or "").strip()
        ]
        total = len(block)
        print(f"{lang}: ключей={total}, совпадает с en={len(same_as_en)}")
        if args.lang and same_as_en:
            print(f"  примеры (первые {args.limit}):")
            for k in same_as_en[: args.limit]:
                print(f"    {k}")


if __name__ == "__main__":
    main()
