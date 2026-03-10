#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Подсчёт продуктов в Supabase. Запуск: python3 scripts/count_products.py"""

import os
import urllib.error
import urllib.request
from typing import Optional

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE"
API_KEY = os.environ.get("SUPABASE_SERVICE_KEY") or ANON_KEY


def fetch_count(filter_params: str = "") -> Optional[int]:
    path = f"/rest/v1/products?select=id&limit=1{filter_params}"
    req = urllib.request.Request(
        SUPABASE_URL + path,
        headers={
            "apikey": API_KEY,
            "Authorization": f"Bearer {API_KEY}",
            "Accept": "application/json",
            "Prefer": "count=exact",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            cr = resp.headers.get("Content-Range")
            if cr and "/" in cr:
                return int(cr.split("/")[1])
    except (urllib.error.HTTPError, OSError) as e:
        print(f"Error: {e}")
    return None


def main():
    total = fetch_count("")
    without = fetch_count("&or=(calories.is.null,calories.eq.0)")
    with_nutrition = fetch_count("&calories=gt.0") if total is not None and without is not None else None
    if with_nutrition is None and total is not None and without is not None:
        with_nutrition = total - without

    print("Продукты в каталоге (Supabase):")
    if total is not None:
        print(f"  Всего:              {total}")
    if without is not None:
        print(f"  Без КБЖУ:           {without}")
    if with_nutrition is not None:
        print(f"  С КБЖУ (заполнено): {with_nutrition}")
    if total is None:
        print("  (не удалось получить данные)")


if __name__ == "__main__":
    main()
