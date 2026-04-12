#!/usr/bin/env python3
"""
Заполнить несколько локалей за один прогон: где значение совпадает с `en`, а в `ru` уже другой текст,
переводим с русского в целевой язык (Google через deep-translator).

Требует: pip install deep-translator

Примеры (из каталога restodocks_flutter):
  # Только «тяжёлые» префиксы UI (см. i18n_fill_from_ru_mt.py)
  python3 scripts/i18n_fill_all_locales_from_ru.py --priority-only --langs de,kk

  # Все языки, все ключи с зазором en (очень долго, риск лимитов API)
  python3 scripts/i18n_fill_all_locales_from_ru.py --langs de,es,fr,it,tr,vi,kk

Перед записью создаётся localizable.json.bak.
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

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))
from i18n_fill_from_ru_mt import gap_keys  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets" / "translations" / "localizable.json"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--langs",
        required=True,
        help="Коды через запятую: de,es,fr,it,tr,vi,kk",
    )
    ap.add_argument("--priority-only", action="store_true")
    ap.add_argument("--batch-size", type=int, default=20)
    ap.add_argument("--sleep", type=float, default=0.6)
    args = ap.parse_args()

    langs = [x.strip() for x in args.langs.split(",") if x.strip()]
    for code in langs:
        if code not in ("de", "es", "fr", "it", "tr", "vi", "kk"):
            print(f"Unsupported lang: {code}", file=sys.stderr)
            sys.exit(1)

    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    ru = data["ru"]

    # Ключи: объединение зазоров по выбранным языкам (один перевод ru→L на ключ)
    key_set: set[str] = set()
    for lang in langs:
        keys = gap_keys(data, lang, args.priority_only)
        key_set |= set(keys)

    keys_sorted = sorted(key_set)
    if not keys_sorted:
        print("Nothing to fill.")
        return

    print(
        f"Keys to translate (union): {len(keys_sorted)}; "
        f"langs={langs}; priority_only={args.priority_only}"
    )

    bak = JSON_PATH.with_suffix(".json.bak")
    shutil.copy2(JSON_PATH, bak)
    print(f"Backup: {bak}")

    translators = {lang: GoogleTranslator(source="ru", target=lang) for lang in langs}

    for i in range(0, len(keys_sorted), args.batch_size):
        chunk = keys_sorted[i : i + args.batch_size]
        texts = [ru[k] for k in chunk]
        for lang in langs:
            tr = translators[lang]
            loc = data[lang]
            try:
                translated = tr.translate_batch(texts)
            except Exception as e:
                print(f"batch error {lang}: {e}, per-line")
                translated = []
                for t in texts:
                    try:
                        translated.append(tr.translate(t))
                        time.sleep(0.12)
                    except Exception as e2:
                        print(f"  skip: {e2}")
                        translated.append(t)
            if len(translated) != len(chunk):
                print("length mismatch", lang, file=sys.stderr)
                sys.exit(1)
            for k, t in zip(chunk, translated):
                loc[k] = t
        done = min(i + args.batch_size, len(keys_sorted))
        print(f"  {done}/{len(keys_sorted)}")
        time.sleep(args.sleep)

    JSON_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Done.")


if __name__ == "__main__":
    main()
