#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Пересчитать КБЖУ ингредиентов ТТК из продуктов.

Обновляет final_calories, final_protein, final_fat, final_carbs в tt_ingredients,
используя products.calories/protein/fat/carbs и (опционально) cooking_processes
(множители ужарки).

Обрабатываются только ингредиенты с product_id (не полуфабрикаты).

  export SUPABASE_SERVICE_KEY='ключ'
  python3 scripts/backfill_ttk_nutrition.py --dry-run   # Показать без записи
  python3 scripts/backfill_ttk_nutrition.py             # Применить
"""

import json
import os
import sys
from typing import Any, Optional

import urllib.error
import urllib.request

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
if not SERVICE_KEY:
    print("Задайте SUPABASE_SERVICE_KEY")
    sys.exit(1)


def _req(method: str, path: str, data: Optional[dict] = None) -> tuple[bool, Any]:
    url = f"{SUPABASE_URL}{path}"
    headers = {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Accept": "application/json",
        "Prefer": "return=minimal",
    }
    body = json.dumps(data).encode("utf-8") if data else None
    if body:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return True, None
    except urllib.error.HTTPError as e:
        return False, e.code


def fetch_all(path: str, select: str, order: str = "id") -> list[dict]:
    out = []
    offset = 0
    while True:
        url = f"{SUPABASE_URL}{path}?select={select}&order={order}&limit=500&offset={offset}"
        req = urllib.request.Request(
            url,
            headers={
                "apikey": SERVICE_KEY,
                "Authorization": f"Bearer {SERVICE_KEY}",
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            batch = json.loads(resp.read().decode())
        if not batch:
            break
        out.extend(batch)
        if len(batch) < 500:
            break
        offset += 500
    return out


def main():
    dry_run = "--dry-run" in sys.argv

    # Ингредиенты с product_id (не полуфабрикаты)
    ingredients = fetch_all(
        "/rest/v1/tt_ingredients",
        "id,product_id,net_weight,gross_weight,cooking_process_id,final_calories,final_protein,final_fat,final_carbs",
    )
    # Фильтр: только с product_id
    ingredients = [i for i in ingredients if i.get("product_id")]

    if not ingredients:
        print("Ингредиентов с product_id не найдено.")
        return

    print(f"Ингредиентов с product_id: {len(ingredients)}")

    # Продукты: id -> nutrition
    products_raw = fetch_all(
        "/rest/v1/products",
        "id,name,calories,protein,fat,carbs",
    )
    products = {p["id"]: p for p in products_raw}

    # Способы приготовления
    processes_raw = fetch_all(
        "/rest/v1/cooking_processes",
        "id,calorie_multiplier,protein_multiplier,fat_multiplier,carbs_multiplier",
    )
    processes = {p["id"]: p for p in processes_raw}

    updated = 0
    skipped_no_nutrition = 0
    skipped_no_change = 0

    for ing in ingredients:
        pid = ing["product_id"]
        p = products.get(pid)
        if not p:
            continue

        cal = p.get("calories") or 0
        prot = p.get("protein") or 0
        fat_val = p.get("fat") or 0
        carb = p.get("carbs") or 0

        if cal == 0 and prot == 0 and fat_val == 0 and carb == 0:
            skipped_no_nutrition += 1
            continue

        net = float(ing.get("net_weight") or ing.get("gross_weight") or 0)
        if net <= 0:
            continue

        mult = net / 100.0

        cp_id = ing.get("cooking_process_id")
        if cp_id and cp_id in processes:
            cp = processes[cp_id]
            cal_mult = float(cp.get("calorie_multiplier") or 1.0)
            prot_mult = float(cp.get("protein_multiplier") or 1.0)
            fat_mult = float(cp.get("fat_multiplier") or 1.0)
            carb_mult = float(cp.get("carbs_multiplier") or 1.0)
            new_cal = cal * mult * cal_mult
            new_prot = prot * mult * prot_mult
            new_fat = fat_val * mult * fat_mult
            new_carb = carb * mult * carb_mult
        else:
            new_cal = cal * mult
            new_prot = prot * mult
            new_fat = fat_val * mult
            new_carb = carb * mult

        if dry_run:
            old_cal = float(ing.get("final_calories") or 0)
            if abs(new_cal - old_cal) < 0.5:
                skipped_no_change += 1
                continue
            pname = products.get(pid, {}).get("name", "")[:30] if pid else ""
            print(f"  {ing['id'][:8]}… {pname!r}: {old_cal:.0f} → {new_cal:.0f} ккал")
            updated += 1
            continue

        payload = {
            "final_calories": round(new_cal, 2),
            "final_protein": round(new_prot, 2),
            "final_fat": round(new_fat, 2),
            "final_carbs": round(new_carb, 2),
        }

        path = f"/rest/v1/tt_ingredients?id=eq.{ing['id']}"
        ok, err = _req("PATCH", path, payload)
        if ok:
            updated += 1
        else:
            print(f"  Ошибка {ing['id'][:8]}…: {err}")

    print(f"\nОбновлено: {updated}")
    if skipped_no_nutrition:
        print(f"Пропущено (нет КБЖУ у продукта): {skipped_no_nutrition}")
    if dry_run and skipped_no_change:
        print(f"Без изменений: {skipped_no_change}")


if __name__ == "__main__":
    main()
