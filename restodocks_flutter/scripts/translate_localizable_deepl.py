#!/usr/bin/env python3
"""Translate localizable.json to Vietnamese (vi) via DeepL (Edge Function translate-text).

Requires:
  export SUPABASE_URL=https://YOUR_PROJECT.supabase.co
  export SUPABASE_ANON_KEY=your_anon_key
  # or SUPABASE_SERVICE_ROLE_KEY

Usage:
  python translate_localizable_deepl.py           # translate en -> vi
  python translate_localizable_deepl.py --dry-run # show what would be translated
"""
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    print("Run: pip install requests")
    sys.exit(1)


def preserve_placeholders(text: str) -> tuple[str, list]:
    placeholders = []

    def repl(m):
        placeholders.append(m.group(0))
        return f"__PH{len(placeholders)-1}__"

    clean = re.sub(r"\{[^}]+\}|%s|%\d+s", repl, text)
    return clean, placeholders


def restore_placeholders(text: str, replacements: list) -> str:
    for i, ph in enumerate(replacements):
        text = text.replace(f"__PH{i}__", ph, 1)
    return text


def translate_via_deepl(text: str, supabase_url: str, key: str, from_lang: str = "EN", to_lang: str = "VI") -> str | None:
    """Call translate-text Edge Function. Returns translated text or None."""
    url = f"{supabase_url.rstrip('/')}/functions/v1/translate-text"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    payload = {"text": text, "from": from_lang, "to": to_lang}
    try:
        r = requests.post(url, json=payload, headers=headers, timeout=30)
        if r.status_code != 200:
            print(f"  API error {r.status_code}: {r.text[:200]}")
            return None
        data = r.json()
        return data.get("translatedText", "").strip()
    except Exception as e:
        print(f"  Request error: {e}")
        return None


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Translate localizable.json to Vietnamese via DeepL")
    parser.add_argument("--dry-run", action="store_true", help="Don't save, just show progress")
    parser.add_argument("--delay", type=float, default=0.25, help="Delay between API calls (default 0.25)")
    parser.add_argument("--source", default="en", help="Source language (default en)")
    parser.add_argument("--target", default="vi", help="Target language (default vi)")
    args = parser.parse_args()

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_ANON_KEY")
    if not url or not key:
        print("Set SUPABASE_URL and SUPABASE_ANON_KEY (or SUPABASE_SERVICE_ROLE_KEY)")
        sys.exit(1)

    root = Path(__file__).parent.parent
    path = root / "assets/translations/localizable.json"
    # Бэкап перед переводом
    from datetime import datetime
    import shutil
    bak = path.with_suffix(f".json.bak.{datetime.now().strftime('%Y%m%d_%H%M%S')}")
    shutil.copy(path, bak)
    print(f"Backup: {bak.name}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    source = data.get(args.source, {})
    if not source:
        print(f"No '{args.source}' section found")
        sys.exit(1)

    # DeepL codes: en->EN, vi->VI
    from_code = args.source.upper() if len(args.source) == 2 else "EN"
    to_code = args.target.upper() if len(args.target) == 2 else "VI"

    keys = list(source.keys())
    result = {}
    ok = 0
    fail = 0

    print(f"Translating {len(keys)} keys from {args.source} to {args.target} via DeepL...")
    if args.dry_run:
        print("(dry-run, no save)")

    for i, k in enumerate(keys):
        orig = str(source[k] or "")
        if not orig.strip():
            result[k] = orig
            ok += 1
            continue

        clean, phs = preserve_placeholders(orig)
        if not clean.strip():
            result[k] = orig
            ok += 1
            continue

        trans = translate_via_deepl(clean, url, key, from_code, to_code)
        if trans:
            result[k] = restore_placeholders(trans, phs)
            ok += 1
        else:
            result[k] = orig
            fail += 1

        if (i + 1) % 50 == 0:
            print(f"  {i+1}/{len(keys)}...")
        time.sleep(args.delay)

    print(f"Done. ok={ok}, fail={fail}")

    if not args.dry_run and result:
        # Слияние: сохраняем существующие ключи, новые переводы перезаписывают
        existing = data.get(args.target) or {}
        merged = {**existing, **result}
        data[args.target] = merged
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        preserved = len(merged) - len(result)
        print(f"Saved {args.target}: {len(result)} translated, {max(0, preserved)} preserved, total {len(merged)} keys.")


if __name__ == "__main__":
    main()
