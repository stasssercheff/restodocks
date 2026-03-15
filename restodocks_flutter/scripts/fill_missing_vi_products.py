#!/usr/bin/env python3
"""
Заполняет вьетнамский (vi) для продуктов, где DeepL не смог перевести.
Использует Google Translate как fallback.

Требует: SUPABASE_SERVICE_ROLE_KEY (из Supabase Dashboard → Settings → API).
С anon key может вернуть 0 продуктов из‑за RLS.
"""
import os
import re
import sys
import time
from pathlib import Path
from typing import Optional, Tuple

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("pip install deep-translator")
    sys.exit(1)

import requests

SUPABASE_REST = "/rest/v1"


def _load_from_main_dart() -> Tuple[Optional[str], Optional[str]]:
    root = Path(__file__).parent.parent
    main_dart = root / "lib" / "main.dart"
    if not main_dart.exists():
        return None, None
    text = main_dart.read_text(encoding="utf-8")
    url_m = re.search(r"SUPABASE_URL.*?defaultValue:\s*['\"]([^'\"]+)['\"]", text, re.DOTALL)
    key_m = re.search(r"SUPABASE_ANON_KEY.*?defaultValue:\s*['\"]([^'\"]+)['\"]", text, re.DOTALL)
    return (url_m.group(1) if url_m else None), (key_m.group(1) if key_m else None)


def translate_to_vi(text: str, source_lang: str = "ru") -> Optional[str]:
    if not text or not text.strip():
        return None
    try:
        return GoogleTranslator(source=source_lang, target="vi").translate(text.strip())
    except Exception as e:
        print(f"    Google err: {e}")
        return None


def main():
    url = os.environ.get("SUPABASE_URL", "").rstrip("/") or None
    key = (
        os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        or os.environ.get("SUPABASE_ANON_KEY")
    )
    if url and ("your_project" in url.lower() or "YOUR_PROJECT" in url):
        url = None
    if key and ("your_anon_key" in key.lower() or "your_key" in key.lower()):
        key = None
    if not url or not key:
        u, k = _load_from_main_dart()
        url = url or u
        key = key or k
    if not url or not key:
        print("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY)")
        sys.exit(1)
    url = url.rstrip("/")

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }

    # Загружаем все продукты (нужен service_role для обхода RLS при прямом доступе)
    print("Loading products...")
    all_products = []
    offset = 0
    page_size = 1000
    while True:
        r = requests.get(
            f"{url}{SUPABASE_REST}/products",
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
                "Range": f"{offset}-{offset + page_size - 1}",
            },
            params={"select": "id,name,names", "order": "name.asc"},
            timeout=60,
        )
        if r.status_code != 200:
            print(f"Error {r.status_code}: {r.text[:300]}")
            print("Tip: use SUPABASE_SERVICE_ROLE_KEY from Dashboard → Settings → API")
            sys.exit(1)
        data = r.json()
        if not data:
            break
        all_products.extend(data)
        if len(data) < page_size:
            break
        offset += page_size

    print(f"Loaded {len(all_products)} products")

    missing_vi = []
    for p in all_products:
        names = p.get("names") or {}
        if isinstance(names, dict):
            vi = (names.get("vi") or "").strip()
            if vi:
                continue
        name = (p.get("name") or "").strip()
        if not name:
            continue
        source = (
            (names.get("ru") or "").strip()
            or (names.get("en") or "").strip()
            or name
        )
        missing_vi.append(
            {"id": p["id"], "name": name, "names": dict(names), "source": source}
        )

    if not missing_vi:
        print("All products already have Vietnamese. Done.")
        return

    print(f"Found {len(missing_vi)} products missing 'vi'. Translating...")

    updated = 0
    for i, p in enumerate(missing_vi):
        trans = translate_to_vi(p["source"], "ru" if "ru" in (p["names"] or {}) else "en")
        if not trans:
            continue
        new_names = {**(p["names"] or {}), "vi": trans}
        r = requests.patch(
            f"{url}{SUPABASE_REST}/products",
            headers=headers,
            params={"id": f"eq.{p['id']}"},
            json={"names": new_names},
            timeout=30,
        )
        if r.status_code in (200, 204):
            updated += 1
        else:
            print(f"  Update fail {p['id']}: {r.status_code} {r.text[:100]}")
        if (i + 1) % 20 == 0:
            print(f"  {i + 1}/{len(missing_vi)}...")
        time.sleep(0.15)

    print(f"Done. Updated {updated}/{len(missing_vi)} products with Vietnamese.")


if __name__ == "__main__":
    main()
