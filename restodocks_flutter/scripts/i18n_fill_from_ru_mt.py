#!/usr/bin/env python3
"""
Fill locales where values still match English by translating from Russian.

Requires: pip install deep-translator

Usage:
  python3 scripts/i18n_fill_from_ru_mt.py --lang de --priority-only
  python3 scripts/i18n_fill_from_ru_mt.py --lang kk --priority-only
  python3 scripts/i18n_fill_from_ru_mt.py --lang de   # all gaps (slow)

Backs up JSON to assets/translations/localizable.json.bak before write.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("Install: pip install deep-translator", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets/translations/localizable.json"

# High-traffic UI: docs, settings, checklists, notifications, schedule/sales shell.
_PRIORITY_EXACT = frozenset(
    {
        "documentation",
        "checklists",
        "language",
        "appearance",
        "establishments",
        "not_specified",
        "optional",
    }
)
_PRIORITY_PREFIXES = (
    "documentation_",
    "checklist_",
    "settings_",
    "notification_",
    "inbox_",
    "inbox_tab_",
    "inbox_title_",
    "inbox_header_",
    "inbox_doc_",
    "doc_type_",
    "order_list_",
    "order_tab_",
    "pos_orders_",
    "department_",
    "birthday_",
    "account_display",
    "fiscal_settings",
    "haccp_journals",
    "establishments_manage",
    "establishments_",
    "sales_financials",
    "system_error",
    "haccp_agreement",
    "role_",
    "dept_",
    "employees_section",
    "employee_register",
    "search_checklist",
    "no_deadline",
    "items_checklist",
    "payroll_",
    "procurement_",
    "inventory_",
    "product_order",
    "writeoff",
    "schedule_",
    "menu_tab_",
    "foodcost_",
)


def _is_priority_key(k: str) -> bool:
    if k in _PRIORITY_EXACT:
        return True
    return k.startswith(_PRIORITY_PREFIXES)


def gap_keys(data: dict, lang: str, priority_only: bool) -> list[str]:
    en = data["en"]
    ru = data["ru"]
    loc = data[lang]
    out: list[str] = []
    for k in en:
        if loc.get(k) == en.get(k) and ru.get(k) not in (None, "") and ru.get(k) != en.get(k):
            if not priority_only or _is_priority_key(k):
                out.append(k)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--lang",
        required=True,
        choices=["de", "es", "fr", "it", "tr", "vi", "kk"],
        help="Целевая локаль (источник текстов — ru)",
    )
    ap.add_argument("--priority-only", action="store_true")
    ap.add_argument("--batch-size", type=int, default=25)
    ap.add_argument("--sleep", type=float, default=0.8, help="Seconds between batches")
    ap.add_argument(
        "--no-save-every-batch",
        action="store_false",
        dest="save_every_batch",
        help="Писать JSON только в конце (по умолчанию — после каждого батча, чтобы не терять прогресс)",
    )
    ap.set_defaults(save_every_batch=True)
    args = ap.parse_args()

    with JSON_PATH.open(encoding="utf-8") as f:
        data = json.load(f)

    keys = gap_keys(data, args.lang, args.priority_only)
    if not keys:
        print("No gaps to fill.")
        return

    tgt = args.lang
    translator = GoogleTranslator(source="ru", target=tgt)

    print(f"Filling {len(keys)} keys for {args.lang} (priority_only={args.priority_only})")

    bak = JSON_PATH.with_suffix(".json.bak")
    shutil.copy2(JSON_PATH, bak)
    print(f"Backup: {bak}")

    ru = data["ru"]
    loc = data[args.lang]
    failed: list[str] = []

    def _write_json() -> None:
        with JSON_PATH.open("w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")

    for i in range(0, len(keys), args.batch_size):
        chunk = keys[i : i + args.batch_size]
        texts = [ru[k] for k in chunk]
        try:
            translated = translator.translate_batch(texts)
        except Exception as e:
            print(f"Batch error at {i}: {e}, falling back to per-string")
            translated = []
            for k in chunk:
                try:
                    translated.append(translator.translate(ru[k]))
                    time.sleep(0.15)
                except Exception as e2:
                    print(f"  skip {k}: {e2}")
                    failed.append(k)
                    translated.append(loc.get(k, ru[k]))
        if len(translated) != len(chunk):
            print("Length mismatch, aborting")
            sys.exit(1)
        for k, t in zip(chunk, translated):
            loc[k] = t
        done = min(i + args.batch_size, len(keys))
        print(f"  {done}/{len(keys)}", flush=True)
        if args.save_every_batch:
            _write_json()
        time.sleep(args.sleep)

    if not args.save_every_batch:
        _write_json()

    if failed:
        print("Failed keys:", len(failed), file=sys.stderr)
    print("Done.")


if __name__ == "__main__":
    main()
