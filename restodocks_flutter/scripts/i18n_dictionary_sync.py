#!/usr/bin/env python3
"""
Синхронизация localizable.json: один набор ключей по всем языкам.

- База ключей: объединение ключей из `en` и всех остальных блоков (чтобы не потерять «висячие» ключи).
- Каждый язык получает все ключи; отсутствующие заполняются из `en` (или из ru для ru-приоритета не требуется — копируем en).
- Ключи только в одном языке: попадают в `en` с подстановкой по умолчанию, затем копируются в остальные.

Запуск из каталога restodocks_flutter:
  python3 scripts/i18n_dictionary_sync.py
  python3 scripts/i18n_dictionary_sync.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets" / "translations" / "localizable.json"

# Порядок блоков в файле (для стабильного diff при желании можно сортировать ключи).
LANG_CODES = ("ru", "en", "es", "kk", "de", "fr", "it", "tr", "vi")

# Подстановки для ключей, которые когда-то добавили только в kk и т.п.
_EN_DEFAULTS: dict[str, str] = {
    "messages": "Messages",
    "purchasing": "Purchasing",
}

# После добавления новых ключей в `ru` при необходимости поправить вручную
# (sync подставляет из `en`, если ключа не было в блоке языка).


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="Только отчёт, без записи файла")
    args = ap.parse_args()

    raw = json.loads(JSON_PATH.read_text(encoding="utf-8"))

    if "en" not in raw:
        print("error: no 'en' block", file=sys.stderr)
        sys.exit(1)

    en: dict[str, str] = raw["en"]

    # Все ключи из всех известных блоков
    all_keys: set[str] = set(en.keys())
    for code in LANG_CODES:
        if code in raw and isinstance(raw[code], dict):
            all_keys |= set(raw[code].keys())

    # Гарантируем наличие в en для любого ключа
    for k in sorted(all_keys):
        if k not in en:
            en[k] = _EN_DEFAULTS.get(k, raw.get("kk", {}).get(k) or raw.get("ru", {}).get(k) or k)

    stats: dict[str, dict[str, int]] = {}

    for code in LANG_CODES:
        if code not in raw:
            raw[code] = {}
        block: dict[str, str] = raw[code]
        added = 0
        for k in all_keys:
            if k not in block:
                block[k] = en[k]
                added += 1
        stats[code] = {"added": added, "total": len(block)}
        # Удаляем ключи не из базы (опционально строгое выравнивание)
        orphan = [k for k in list(block.keys()) if k not in all_keys]
        for k in orphan:
            del block[k]

    if args.dry_run:
        print("Dry run — no file written.")
        for code in LANG_CODES:
            s = stats.get(code, {})
            print(f"  {code}: would have total_keys={s.get('total')}, added_missing={s.get('added')}")
        print(f"  canonical key count: {len(all_keys)}")
        return

    tmp = JSON_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(raw, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(JSON_PATH)
    print("Wrote", JSON_PATH)
    for code in LANG_CODES:
        s = stats.get(code, {})
        print(f"  {code}: keys={s.get('total')}, filled_missing={s.get('added')}")


if __name__ == "__main__":
    main()
