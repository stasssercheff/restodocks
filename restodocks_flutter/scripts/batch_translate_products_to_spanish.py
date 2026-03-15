#!/usr/bin/env python3
"""
Пакетный перевод продуктов на все поддерживаемые языки (ru, en, es, tr, vi).
Вызывает Edge Function auto-translate-product в режиме batch.

ВАЖНО: перед запуском задеплойте Edge Function:
  cd restodocks_flutter
  supabase functions deploy auto-translate-product

Использование:
  python batch_translate_products_to_spanish.py   # перевести ВСЕ продукты
  python batch_translate_products_to_spanish.py --max-batches 5   # только 5 батчей (тест)

  SUPABASE_URL и SUPABASE_ANON_KEY берутся из lib/main.dart, если не заданы в env.
"""
import os
import re
import sys
import time
import argparse
from pathlib import Path
from typing import Optional, Tuple

import requests

BATCH_SIZE = 30  # меньше = меньше 502 таймаутов (5 языков × 30 = 150 вызовов DeepL)


def _load_from_main_dart() -> Tuple[Optional[str], Optional[str]]:
    """Извлечь SUPABASE_URL и SUPABASE_ANON_KEY из lib/main.dart (defaultValue)."""
    root = Path(__file__).parent.parent
    main_dart = root / "lib" / "main.dart"
    if not main_dart.exists():
        return None, None
    text = main_dart.read_text(encoding="utf-8")
    url_m = re.search(r"SUPABASE_URL.*?defaultValue:\s*['\"]([^'\"]+)['\"]", text, re.DOTALL)
    key_m = re.search(r"SUPABASE_ANON_KEY.*?defaultValue:\s*['\"]([^'\"]+)['\"]", text, re.DOTALL)
    return (url_m.group(1) if url_m else None), (key_m.group(1) if key_m else None)


def main():
    parser = argparse.ArgumentParser(description="Batch translate products to all languages")
    parser.add_argument("--max-batches", type=int, default=None,
                        help="Max number of batches (default: unlimited)")
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE,
                        help=f"Batch size (default: {BATCH_SIZE})")
    parser.add_argument("--force-vi", action="store_true",
                        help="Force re-translate Vietnamese even if exists (for fix)")
    parser.add_argument("--start-offset", type=int, default=0,
                        help="Start from offset (to resume after 502)")
    args = parser.parse_args()

    url = os.environ.get("SUPABASE_URL", "").rstrip("/") or None
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_ANON_KEY")
    # Игнорировать плейсхолдеры (YOUR_PROJECT, your_anon_key и т.п.)
    if url and ("your_project" in url.lower() or "YOUR_PROJECT" in url):
        url = None
    if key and ("your_anon_key" in key.lower() or "your_key" in key.lower()):
        key = None
    if not url or not key:
        fallback_url, fallback_key = _load_from_main_dart()
        url = url or fallback_url
        key = key or fallback_key
    if not url or not key:
        print("Set SUPABASE_URL and SUPABASE_ANON_KEY (or SUPABASE_SERVICE_ROLE_KEY)")
        print("  export SUPABASE_URL=https://YOUR_PROJECT.supabase.co")
        print("  export SUPABASE_ANON_KEY=your_anon_key")
        sys.exit(1)
    url = url.rstrip("/")

    fn_url = f"{url}/functions/v1/auto-translate-product"
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }

    offset = args.start_offset
    total_translated = 0
    total_skipped = 0
    total_failed = 0
    batch_num = 0

    print(f"Starting batch translation to ru/en/es/tr/vi (batch_size={args.batch_size})")
    if offset > 0:
        print(f"Resuming from offset {offset}")
    print("-" * 50)

    while True:
        if args.max_batches is not None and batch_num >= args.max_batches:
            print(f"Reached max batches ({args.max_batches})")
            break

        payload: dict = {"batch": True, "limit": args.batch_size, "offset": offset}
        if args.force_vi:
            payload["force_langs"] = ["vi"]
        for attempt in range(3):
            try:
                resp = requests.post(
                    fn_url,
                    headers=headers,
                    json=payload,
                    timeout=180,
                )
            except requests.RequestException as e:
                print(f"Request error (attempt {attempt + 1}/3): {e}")
                if attempt < 2:
                    time.sleep(10)
                    continue
                sys.exit(1)

            if resp.status_code == 502 or resp.status_code == 504:
                print(f"  [offset {offset}] {resp.status_code} (attempt {attempt + 1}/3), retry in 15s...")
                if attempt < 2:
                    time.sleep(15)
                    continue
            if resp.status_code != 200:
                print(f"Error {resp.status_code}: {resp.text[:500]}")
                sys.exit(1)
            break

        data = resp.json()
        translated = data.get("translated", 0)
        skipped = data.get("skipped", 0)
        failed = data.get("failed", 0)
        batch_size = data.get("batch_size", 0)
        has_more = data.get("has_more", False)

        total_translated += translated
        total_skipped += skipped
        total_failed += failed
        batch_num += 1

        print(f"  [offset {offset}] translated={translated}, skipped={skipped}, failed={failed}")

        if batch_size < args.batch_size or not has_more:
            break

        offset += args.batch_size
        time.sleep(2)  # пауза между батчами (снижает 502)

    print("-" * 50)
    print(f"Done. Total: translated={total_translated}, skipped={total_skipped}, failed={total_failed}")


if __name__ == "__main__":
    main()
