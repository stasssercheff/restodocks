#!/usr/bin/env python3
"""
Отчёт по словарю localizable.json: сколько ключей совпадает с en (плейсхолдеры),
по каким языкам; опционально список ключей для выгрузки в перевод.

См. также:
  scripts/i18n_dictionary_sync.py   — одинаковый набор ключей во всех языках
  scripts/i18n_scan_hardcoded.py    — поиск Text(...)/label без loc.t (эвристика)
  scripts/i18n_fill_from_ru_mt.py   — перевод зазоров ru→одна локаль
  scripts/i18n_fill_all_locales_from_ru.py — ru→несколько локалей за прогон

Запуск из корня репозитория:
  python3 restodocks_flutter/scripts/i18n_gap_report.py
  python3 restodocks_flutter/scripts/i18n_gap_report.py --lang kk --limit 80
  python3 restodocks_flutter/scripts/i18n_gap_report.py --parity
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
    ap.add_argument(
        "--parity",
        action="store_true",
        help="Проверить, что у каждого языка тот же набор ключей, что и у en",
    )
    args = ap.parse_args()

    with JSON_PATH.open(encoding="utf-8") as f:
        data: dict[str, dict[str, str]] = json.load(f)

    en = data.get("en", {})
    en_keys = set(en.keys())

    if args.parity:
        print(f"en: эталонных ключей = {len(en_keys)}")
        for lang in sorted(k for k in data if k != "en"):
            block = data.get(lang, {})
            sk = set(block.keys())
            missing = en_keys - sk
            extra = sk - en_keys
            print(
                f"  {lang}: ключей={len(sk)}  "
                f"нет в блоке (vs en): {len(missing)}  лишних (vs en): {len(extra)}"
            )
            if missing and len(missing) <= 12:
                print(f"    missing: {sorted(missing)}")
            if extra and len(extra) <= 12:
                print(f"    extra: {sorted(extra)}")
        return

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
