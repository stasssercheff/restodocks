#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Применить ручной КБЖУ из CSV в БД.
Файл: scripts/products_without_kbju.csv (создаётся export_products_without_kbju.py)

Использование:
  export SUPABASE_SERVICE_KEY='ключ'
  python3 scripts/apply_manual_kbju.py
  python3 scripts/apply_manual_kbju.py --dry-run  # Без записи в БД
"""

import csv
import json
import urllib.error
import os
import sys
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_CSV = os.path.join(SCRIPT_DIR, "products_without_kbju.csv")

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
if not SERVICE_KEY:
    print("Задайте SUPABASE_SERVICE_KEY")
    sys.exit(1)


def parse_num(s):
    if not s or not str(s).strip():
        return None
    try:
        return float(str(s).replace(",", ".").strip())
    except ValueError:
        return None


def parse_bool(s):
    if not s:
        return None
    v = str(s).strip().lower()
    if v in ("true", "1", "yes", "да"):
        return True
    if v in ("false", "0", "no", "нет"):
        return False
    return None


def update_product(product_id: str, data: dict) -> bool:
    body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/products?id=eq.{product_id}",
        data=body,
        headers={
            "apikey": SERVICE_KEY,
            "Authorization": f"Bearer {SERVICE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
        method="PATCH",
    )
    try:
        with urllib.request.urlopen(req, timeout=30):
            return True
    except urllib.error.HTTPError as e:
        print(f"  Ошибка {product_id}: {e.code}")
        return False


def main():
    dry_run = "--dry-run" in sys.argv
    if not os.path.exists(INPUT_CSV):
        print(f"Файл не найден: {INPUT_CSV}")
        print("Сначала: python3 scripts/export_products_without_kbju.py")
        sys.exit(1)

    rows = []
    with open(INPUT_CSV, "r", encoding="utf-8") as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            rows.append(row)

    updated = 0
    skipped = 0
    for row in rows:
        product_id = (row.get("id") or "").strip()
        name = (row.get("name") or "").strip()
        calories = parse_num(row.get("calories"))
        protein = parse_num(row.get("protein"))
        fat = parse_num(row.get("fat"))
        carbs = parse_num(row.get("carbs"))
        gl = parse_bool(row.get("contains_gluten"))
        lac = parse_bool(row.get("contains_lactose"))

        if not product_id:
            continue
        if calories is None and protein is None and fat is None and carbs is None and gl is None and lac is None:
            skipped += 1
            continue

        data = {}
        if calories is not None:
            data["calories"] = calories
        if protein is not None:
            data["protein"] = protein
        if fat is not None:
            data["fat"] = fat
        if carbs is not None:
            data["carbs"] = carbs
        if gl is not None:
            data["contains_gluten"] = gl
        if lac is not None:
            data["contains_lactose"] = lac

        if not data:
            skipped += 1
            continue

        if dry_run:
            print(f"[DRY-RUN] {name}: {data}")
        else:
            if update_product(product_id, data):
                updated += 1
                print(f"✓ {name}")
            else:
                print(f"✗ {name}")

    print(f"\nОбновлено: {updated}, пропущено: {skipped}")


if __name__ == "__main__":
    main()
