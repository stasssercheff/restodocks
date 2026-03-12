#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Убрать из названий продуктов «VND» и префикс «Т.» в БД.

Использование:
  export SUPABASE_SERVICE_KEY='ключ'
  python3 scripts/clean_product_names.py --dry-run   # Показать изменения без записи
  python3 scripts/clean_product_names.py             # Применить
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
if not SERVICE_KEY:
    print("Задайте SUPABASE_SERVICE_KEY")
    sys.exit(1)


def clean_name(s: str) -> str:
    """Убрать VND и префикс Т./т./T. из названия."""
    if not s or not isinstance(s, str):
        return s
    t = s.strip()
    # Убрать trailing VND (с табом/пробелами)
    t = re.sub(r"[\s\t]+VND\s*$", "", t, flags=re.IGNORECASE)
    # Убрать leading Т. / т. / T.
    t = re.sub(r"^[ТтTt]\.\s*", "", t)
    return t.strip() or s


def fetch_all_products():
    """Получить все продукты (id, name, names)."""
    products = []
    offset = 0
    while True:
        path = f"/rest/v1/products?select=id,name,names&order=name&limit=500&offset={offset}"
        req = urllib.request.Request(
            f"{SUPABASE_URL}{path}",
            headers={
                "apikey": SERVICE_KEY,
                "Authorization": f"Bearer {SERVICE_KEY}",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                batch = json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            print(f"Ошибка: {e.code}")
            sys.exit(1)
        if not batch:
            break
        products.extend(batch)
        if len(batch) < 500:
            break
        offset += 500
    return products


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
    products = fetch_all_products()
    print(f"Продуктов: {len(products)}")

    # Карта name -> id (для проверки конфликтов UNIQUE)
    name_to_id = {p.get("name") or "": p.get("id") for p in products}

    updated = 0
    skipped_conflict = 0
    for p in products:
        pid = p.get("id")
        name = p.get("name") or ""
        names = p.get("names")
        if isinstance(names, dict):
            names = dict(names)
        else:
            names = {}

        new_name = clean_name(name)
        new_names = {}
        names_changed = False
        for k, v in names.items():
            if v and isinstance(v, str):
                cv = clean_name(v)
                new_names[k] = cv
                if cv != v:
                    names_changed = True
            else:
                new_names[k] = v

        if new_name == name and not names_changed:
            continue

        # Конфликт: new_name уже занят другим продуктом (UNIQUE на name)
        if new_name != name:
            other_id = name_to_id.get(new_name)
            if other_id and other_id != pid:
                if not dry_run:
                    skipped_conflict += 1
                continue

        payload = {}
        if new_name != name:
            payload["name"] = new_name
        if names_changed and new_names:
            payload["names"] = new_names

        if not payload:
            continue

        if dry_run:
            print(f"  {name!r} -> {new_name!r}")
        else:
            if update_product(pid, payload):
                updated += 1
                # Обновить карту: старое имя освободилось, новое занято
                if name in name_to_id and name_to_id[name] == pid:
                    del name_to_id[name]
                name_to_id[new_name] = pid
                print(f"✓ {new_name}")

    print(f"\nОбновлено: {updated}")
    if skipped_conflict:
        print(f"Пропущено (дубликат name): {skipped_conflict}")
        print("  Затем: python3 scripts/deduplicate_products.py — объединить дубли и удалить их")


if __name__ == "__main__":
    main()
