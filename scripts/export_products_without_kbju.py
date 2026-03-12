#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Экспорт продуктов без КБЖУ в CSV.
Заполни колонки calories, protein, fat, carbs, contains_gluten, contains_lactose — затем примени через apply_manual_kbju.py.

Использование:
  export SUPABASE_SERVICE_KEY='ключ'
  python3 scripts/export_products_without_kbju.py
  # Создаст scripts/products_without_kbju.csv — заполни данные
  python3 scripts/apply_manual_kbju.py  # Применить
"""

import csv
import json
import os
import sys
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_CSV = os.path.join(SCRIPT_DIR, "products_without_kbju.csv")

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE"
API_KEY = SERVICE_KEY or ANON_KEY


def fetch_products_without_nutrition():
    """Продукты без калорий (нужны КБЖУ)."""
    products = []
    offset = 0
    while True:
        path = f"/rest/v1/products?select=id,name,names&or=(calories.is.null,calories.eq.0)&order=name&limit=500&offset={offset}"
        req = urllib.request.Request(
            f"{SUPABASE_URL}{path}",
            headers={
                "apikey": API_KEY,
                "Authorization": f"Bearer {API_KEY}",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                batch = json.loads(resp.read().decode())
        except Exception as e:
            print(f"Ошибка: {e}")
            sys.exit(1)
        if not batch:
            break
        products.extend(batch)
        if len(batch) < 500:
            break
        offset += 500
    return products


def display_name(p):
    names = p.get("names")
    if isinstance(names, dict):
        ru = (names.get("ru") or names.get("en") or "").strip()
        if ru:
            return ru
    return (p.get("name") or "").strip()


def main():
    print("Загрузка продуктов без КБЖУ из Supabase...")
    products = fetch_products_without_nutrition()
    print(f"Найдено: {len(products)} продуктов")

    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow([
            "id", "name",
            "calories", "protein", "fat", "carbs",
            "contains_gluten", "contains_lactose"
        ])
        for p in products:
            name = display_name(p)
            w.writerow([
                p.get("id", ""),
                name,
                "", "", "", "",  # calories, protein, fat, carbs
                "", "",          # contains_gluten (true/false), contains_lactose (true/false)
            ])

    print(f"Сохранено: {OUTPUT_CSV}")
    print("Заполни колонки calories, protein, fat, carbs, contains_gluten, contains_lactose")
    print("КБЖУ — на 100 г. contains_gluten / contains_lactose: true или false")
    print("Затем: python3 scripts/apply_manual_kbju.py")


if __name__ == "__main__":
    main()
