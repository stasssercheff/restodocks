#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Читает starter_catalog.json и генерирует SQL для вставки продуктов в Supabase (таблица products).
Запуск: python3 scripts/seed_products_from_catalog.py [путь_к_starter_catalog.json]
По умолчанию: ../Restodocks/starter_catalog.json (от корня restodocks_flutter).
Результат: seed_products.sql в текущей директории. Выполните его в Supabase → SQL Editor.
"""
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_CATALOG = os.path.join(REPO_ROOT, "..", "Restodocks", "starter_catalog.json")
OUT_SQL = os.path.join(REPO_ROOT, "seed_products.sql")
BATCH_SIZE = 80


def esc(s):
    if s is None:
        return "NULL"
    return "'" + str(s).replace("\\", "\\\\").replace("'", "''") + "'"


def main():
    catalog_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CATALOG
    if not os.path.isfile(catalog_path):
        print(f"Файл не найден: {catalog_path}")
        print("Укажите путь: python3 seed_products_from_catalog.py /path/to/starter_catalog.json")
        sys.exit(1)

    with open(catalog_path, "r", encoding="utf-8") as f:
        items = json.load(f)

    # Удаляем дубликаты по id
    seen = set()
    unique = []
    for p in items:
        pid = p.get("id") or ""
        if pid and pid not in seen:
            seen.add(pid)
            unique.append(p)

    header = [
        "-- Вставка продуктов из starter_catalog.json в таблицу products (Supabase).",
        "-- Выполните в Supabase → SQL Editor. При повторном запуске сначала: DELETE FROM products;",
        "",
    ]
    inserts = []

    for i in range(0, len(unique), BATCH_SIZE):
        batch = unique[i : i + BATCH_SIZE]
        values = []
        for p in batch:
            uid = (p.get("id") or "").strip()
            name = (p.get("name") or "").strip().replace("'", "''")
            cat = (p.get("category") or "misc").strip().replace("'", "''")
            names = p.get("names") or {}
            names_json = json.dumps(names, ensure_ascii=False).replace("'", "''")
            cal = p.get("calories")
            pr = p.get("protein")
            fa = p.get("fat")
            ca = p.get("carbs")
            gluten = bool(p.get("containsGluten", False))
            lactose = bool(p.get("containsLactose", False))
            unit = (p.get("unit") or "кг").strip().replace("'", "''")

            cal_s = str(float(cal)) if cal is not None else "NULL"
            pr_s = str(float(pr)) if pr is not None else "NULL"
            fa_s = str(float(fa)) if fa is not None else "NULL"
            ca_s = str(float(ca)) if ca is not None else "NULL"

            row = (
                f"({esc(uid)}, {esc(name)}, {esc(cat)}, '{names_json}'::jsonb, "
                f"{cal_s}, {pr_s}, {fa_s}, {ca_s}, {str(gluten).lower()}, {str(lactose).lower()}, {esc(unit)})"
            )
            values.append(row)
        inserts.append(
            "INSERT INTO products (id, name, category, names, calories, protein, fat, carbs, contains_gluten, contains_lactose, unit)\nVALUES\n"
            + ",\n".join(values)
            + ";"
        )

    sql = "\n".join(header) + "\n\n".join(inserts)
    with open(OUT_SQL, "w", encoding="utf-8") as f:
        f.write(sql)

    print(f"Сгенерировано {len(unique)} продуктов → {OUT_SQL}")
    print("Дальше: откройте Supabase → SQL Editor, вставьте содержимое файла и выполните.")


if __name__ == "__main__":
    main()
