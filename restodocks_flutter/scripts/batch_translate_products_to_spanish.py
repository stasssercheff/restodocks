#!/usr/bin/env python3
"""
Пакетный перевод продуктов на испанский.
Вызывает Edge Function auto-translate-product в режиме batch.
Продукты с ru/en, но без es — будут переведены на испанский.

Использование:
  export SUPABASE_URL=https://YOUR_PROJECT.supabase.co
  export SUPABASE_ANON_KEY=your_anon_key
  # или SUPABASE_SERVICE_ROLE_KEY для вызова без RLS
  python batch_translate_products_to_spanish.py

  # Ограничить число батчей (для теста):
  python batch_translate_products_to_spanish.py --max-batches 5
"""
import os
import sys
import time
import argparse
import requests

BATCH_SIZE = 50  # размер батча (как в Edge Function)


def main():
    parser = argparse.ArgumentParser(description="Batch translate products to Spanish")
    parser.add_argument("--max-batches", type=int, default=None,
                        help="Max number of batches (default: unlimited)")
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE,
                        help=f"Batch size (default: {BATCH_SIZE})")
    args = parser.parse_args()

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SUPABASE_ANON_KEY")
    if not url or not key:
        print("Set SUPABASE_URL and SUPABASE_ANON_KEY (or SUPABASE_SERVICE_ROLE_KEY)")
        sys.exit(1)

    fn_url = f"{url}/functions/v1/auto-translate-product"
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }

    offset = 0
    total_translated = 0
    total_skipped = 0
    total_failed = 0
    batch_num = 0

    print(f"Starting batch translation to Spanish (batch_size={args.batch_size})")
    print("-" * 50)

    while True:
        if args.max_batches is not None and batch_num >= args.max_batches:
            print(f"Reached max batches ({args.max_batches})")
            break

        try:
            resp = requests.post(
                fn_url,
                headers=headers,
                json={"batch": True, "limit": args.batch_size, "offset": offset},
                timeout=120,
            )
        except requests.RequestException as e:
            print(f"Request error: {e}")
            sys.exit(1)

        if resp.status_code != 200:
            print(f"Error {resp.status_code}: {resp.text}")
            sys.exit(1)

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
        time.sleep(1)  # пауза между батчами

    print("-" * 50)
    print(f"Done. Total: translated={total_translated}, skipped={total_skipped}, failed={total_failed}")


if __name__ == "__main__":
    main()
