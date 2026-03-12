#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Объединить дубликаты продуктов (одинаковое очищённое имя: без VND, без «Т.»).
Переносит ссылки (establishment_products, product_price_history, tt_ingredients,
product_aliases) на «победителя», затем удаляет дубли.

Порядок: 1) clean_product_names.py (обновить названия без конфликтов)
         2) deduplicate_products.py (объединить дубли)

  export SUPABASE_SERVICE_KEY='ключ'
  python3 scripts/deduplicate_products.py --dry-run   # Показать дубли без изменений
  python3 scripts/deduplicate_products.py             # Выполнить
"""

import json
import os
import re
import sys
from collections import defaultdict
from typing import Any, Optional

import urllib.error
import urllib.request

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
if not SERVICE_KEY:
    print("Задайте SUPABASE_SERVICE_KEY")
    sys.exit(1)


def clean_name(s: str) -> str:
    """Та же логика, что в clean_product_names.py."""
    if not s or not isinstance(s, str):
        return s
    t = s.strip()
    t = re.sub(r"[\s\t]+VND\s*$", "", t, flags=re.IGNORECASE)
    t = re.sub(r"^[ТтTt]\.\s*", "", t)
    return t.strip() or s


def _req(method: str, path: str, data: Optional[dict] = None) -> tuple[bool, Any]:
    url = f"{SUPABASE_URL}{path}"
    headers = {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Accept": "application/json",
        "Prefer": "return=representation",
    }
    body = json.dumps(data).encode("utf-8") if data else None
    if body:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            text = resp.read().decode()
            return True, json.loads(text) if text else []
    except urllib.error.HTTPError as e:
        return False, e.code


def fetch_json(path: str):
    ok, out = _req("GET", path)
    if not ok:
        print(f"Ошибка GET {path}: {out}")
        sys.exit(1)
    return out


def patch_rows(table: str, filter_: str, data: dict) -> bool:
    path = f"/rest/v1/{table}?{filter_}"
    ok, _ = _req("PATCH", path, data)
    return ok


def delete_rows(table: str, filter_: str) -> bool:
    path = f"/rest/v1/{table}?{filter_}"
    ok, _ = _req("DELETE", path)
    return ok


def main():
    dry_run = "--dry-run" in sys.argv

    products = []
    offset = 0
    while True:
        batch = fetch_json(
            f"/rest/v1/products?select=id,name&order=id&limit=500&offset={offset}"
        )
        if not batch:
            break
        products.extend(batch)
        if len(batch) < 500:
            break
        offset += 500

    print(f"Продуктов: {len(products)}")

    # Группы по нормализованному имени
    by_normalized: dict[str, list[dict]] = defaultdict(list)
    for p in products:
        key = clean_name(p.get("name") or "").strip().lower()
        if not key:
            continue
        by_normalized[key].append(p)

    # Кандидаты на объединение (группы с >1 продукта)
    groups = [(k, v) for k, v in by_normalized.items() if len(v) > 1]
    if not groups:
        print("Дублей не найдено.")
        return

    # Определяем победителя в каждой группе
    ep_ids = set()
    try:
        off = 0
        while True:
            batch = fetch_json(
                f"/rest/v1/establishment_products?select=product_id&limit=1000&offset={off}"
            )
            ep_ids.update(r["product_id"] for r in batch)
            if len(batch) < 1000:
                break
            off += 1000
    except Exception:
        pass

    to_merge: list[tuple[str, str, list[str]]] = []  # (norm_name, winner_id, victim_ids)
    for norm_name, prods in groups:
        # Победитель: сначала в establishment_products, иначе min(id)
        in_ep = [p for p in prods if p["id"] in ep_ids]
        if in_ep:
            winner = min(in_ep, key=lambda x: x["id"])
        else:
            winner = min(prods, key=lambda x: x["id"])
        victims = [p["id"] for p in prods if p["id"] != winner["id"]]
        to_merge.append((norm_name, winner["id"], victims))

    print(f"Групп дублей: {len(to_merge)} (будут объединены в победителя)\n")

    if dry_run:
        for norm_name, winner_id, victim_ids in to_merge:
            winner_name = next(p["name"] for p in products if p["id"] == winner_id)
            victim_names = [next(p["name"] for p in products if p["id"] == vid) for vid in victim_ids]
            print(f"  «{norm_name}»: оставить {winner_name!r}, удалить {victim_names}")
        return

    deleted_total = 0
    for norm_name, winner_id, victim_ids in to_merge:
        for vid in victim_ids:
            # 1. establishment_products: перевести на winner или удалить при конфликте
            ep_list = fetch_json(
                f"/rest/v1/establishment_products?select=id,establishment_id,department&product_id=eq.{vid}"
            )
            for ep in ep_list:
                eid, est_id, dept = ep["id"], ep["establishment_id"], ep.get("department") or "kitchen"
                # Есть ли у winner уже запись (est, winner, dept)?
                exists = fetch_json(
                    f"/rest/v1/establishment_products?establishment_id=eq.{est_id}&product_id=eq.{winner_id}&department=eq.{dept}"
                )
                if exists:
                    delete_rows("establishment_products", f"id=eq.{eid}")
                else:
                    patch_rows("establishment_products", f"id=eq.{eid}", {"product_id": winner_id})

            # 2. product_price_history
            patch_rows("product_price_history", f"product_id=eq.{vid}", {"product_id": winner_id})

            # 3. tt_ingredients
            patch_rows("tt_ingredients", f"product_id=eq.{vid}", {"product_id": winner_id})

            # 4. product_aliases
            patch_rows("product_aliases", f"product_id=eq.{vid}", {"product_id": winner_id})

            # 5. Удалить продукт
            delete_rows("products", f"id=eq.{vid}")
            deleted_total += 1
            victim_name = next((p["name"] for p in products if p["id"] == vid), vid)
            print(f"✓ Объединён → {norm_name}: удалён {victim_name!r}")

    print(f"\nУдалено дублей: {deleted_total}")


if __name__ == "__main__":
    main()
