#!/usr/bin/env python3
"""
Дозаполнить kk в localizable.json через DeepL: только ключи, где kk совпадает с en,
а ru отличается (типичный «просев» после MT/синка).

Источник текста для перевода — **ru** (юридически/смыслово ближе к интерфейсу РФ/СНГ).

Требуется один из вариантов:
  export DEEPL_API_KEY=...   # прямой вызов api-free.deepl.com (удобно локально)

или (как translate_localizable_deepl.py):
  export SUPABASE_URL=... SUPABASE_ANON_KEY=...
  — тогда запросы идут в Edge Function translate-text (тот же DeepL на сервере).

Примеры:
  python3 scripts/i18n_deepl_kk_gaps.py --dry-run
  python3 scripts/i18n_deepl_kk_gaps.py --max-keys 80 --delay 0.35
  python3 scripts/i18n_deepl_kk_gaps.py --prefix settings_
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import requests
except ImportError:
    print("pip install requests", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets" / "translations" / "localizable.json"
DEEPL_URL = "https://api-free.deepl.com/v2/translate"


def preserve_placeholders(text: str) -> tuple[str, list[str]]:
    placeholders: list[str] = []

    def repl(m: re.Match) -> str:
        placeholders.append(m.group(0))
        return f"__PH{len(placeholders) - 1}__"

    clean = re.sub(r"\{[^}]+\}|%s|%\d+s", repl, text)
    return clean, placeholders


def restore_placeholders(text: str, placeholders: list[str]) -> str:
    for i, ph in enumerate(placeholders):
        text = text.replace(f"__PH{i}__", ph, 1)
    return text


def translate_deepl_direct(text: str, deepl_key: str) -> str | None:
    r = requests.post(
        DEEPL_URL,
        data={
            "auth_key": deepl_key,
            "text": text,
            "source_lang": "RU",
            "target_lang": "KK",
        },
        timeout=45,
    )
    if not r.ok:
        print(f"  DeepL HTTP {r.status_code}: {r.text[:200]}", file=sys.stderr)
        return None
    data = r.json()
    arr = data.get("translations")
    if not arr:
        return None
    return (arr[0].get("text") or "").strip()


def translate_via_supabase(text: str, url: str, key: str) -> str | None:
    endpoint = f"{url.rstrip('/')}/functions/v1/translate-text"
    r = requests.post(
        endpoint,
        json={"text": text, "from": "RU", "to": "KK"},
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        timeout=45,
    )
    if r.status_code != 200:
        print(f"  Edge {r.status_code}: {r.text[:200]}", file=sys.stderr)
        return None
    data = r.json()
    return (data.get("translatedText") or "").strip() or None


def gap_keys(
    data: dict,
    prefix: str | None,
) -> list[str]:
    en = data.get("en", {})
    ru = data.get("ru", {})
    kk = data.get("kk", {})
    out: list[str] = []
    for k in en:
        if prefix and not k.startswith(prefix):
            continue
        ev = (en.get(k) or "").strip()
        rv = (ru.get(k) or "").strip()
        kv = (kk.get(k) or "").strip()
        if not rv or rv == ev:
            continue
        if kv == ev:
            out.append(k)
    return sorted(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--delay", type=float, default=0.3)
    ap.add_argument("--max-keys", type=int, default=0, help="0 = без лимита")
    ap.add_argument("--prefix", default=None, help="Только ключи с этим префиксом")
    args = ap.parse_args()

    raw = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    keys = gap_keys(raw, args.prefix)
    if args.max_keys > 0:
        keys = keys[: args.max_keys]

    print(f"Ключей с зазором kk==en, ru≠en: {len(keys)}")
    if args.dry_run:
        for k in keys[:40]:
            print(" ", k)
        if len(keys) > 40:
            print(" ...")
        return

    deepl = os.environ.get("DEEPL_API_KEY", "").strip()
    sb_url = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    sb_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get(
        "SUPABASE_ANON_KEY"
    )
    if not deepl and not (sb_url and sb_key):
        print(
            "Задайте DEEPL_API_KEY или SUPABASE_URL + SUPABASE_ANON_KEY",
            file=sys.stderr,
        )
        sys.exit(1)

    bak = JSON_PATH.with_suffix(f".json.bak.{datetime.now().strftime('%Y%m%d_%H%M%S')}")
    shutil.copy2(JSON_PATH, bak)
    print(f"Backup: {bak}")

    ru = raw["ru"]
    kk = raw["kk"]
    ok = fail = 0
    for i, k in enumerate(keys):
        orig = str(ru.get(k) or "")
        if not orig.strip():
            continue
        clean, phs = preserve_placeholders(orig)
        if deepl:
            trans = translate_deepl_direct(clean, deepl)
        else:
            trans = translate_via_supabase(clean, sb_url, sb_key or "")
        if trans:
            kk[k] = restore_placeholders(trans, phs)
            ok += 1
        else:
            fail += 1
        if (i + 1) % 25 == 0:
            print(f"  {i + 1}/{len(keys)} ok={ok} fail={fail}")
        time.sleep(args.delay)

    JSON_PATH.write_text(json.dumps(raw, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Done. updated={ok} fail={fail}")


if __name__ == "__main__":
    main()
