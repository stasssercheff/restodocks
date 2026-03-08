#!/usr/bin/env python3
"""
Заполняет КБЖУ (calories, protein, fat, carbs) в таблице products из Open Food Facts.
Обновляет только продукты, у которых КБЖУ пустые (NULL). КБЖУ только в БД — нигде не отображается.

Использование:
  python3 scripts/fetch_kbju_openfoodfacts.py [SERVICE_ROLE_KEY]
  # или
  export SUPABASE_SERVICE_ROLE_KEY=... && python3 scripts/fetch_kbju_openfoodfacts.py

Open Food Facts: https://world.openfoodfacts.org/ — бесплатный API, без ключа.
Rate limit: ~100 req/min. Скрипт делает паузу 1.5 с между запросами.
"""
import json
import sys
import time
import urllib.request
import urllib.error
import urllib.parse

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
USER_AGENT = "Restodocks/1.0 - Product Database"
OFF_API = "https://world.openfoodfacts.org/cgi/search.pl"


def fetch_products_missing_kbju(api_key):
    """Загружает продукты, у которых calories IS NULL."""
    offset = 0
    products = []
    while True:
        path = (
            f"/rest/v1/products?select=id,name,names&"
            f"calories=is.null&limit=500&offset={offset}"
        )
        req = urllib.request.Request(
            f"{SUPABASE_URL}{path}",
            headers={
                "apikey": api_key,
                "Authorization": f"Bearer {api_key}",
            },
        )
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
        products.extend(data)
        if len(data) < 500:
            break
        offset += 500
    return products


def search_openfoodfacts(query):
    """Ищет продукт в Open Food Facts, возвращает nutriments или None."""
    params = urllib.parse.urlencode({
        "search_terms": query[:100],
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "page_size": 5,
    })
    url = f"{OFF_API}?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError):
        return None
    prods = data.get("products") or []
    for p in prods:
        nut = p.get("nutriments") or {}
        kcal = nut.get("energy-kcal_100g")
        if kcal is None:
            en_kj = nut.get("energy_100g") or nut.get("energy-kj_100g")
            if en_kj is not None:
                kcal = float(en_kj) / 4.184  # kJ -> kcal
        if kcal is None:
            continue
        protein = nut.get("proteins_100g")
        fat = nut.get("fat_100g")
        carbs = nut.get("carbohydrates_100g")
        if protein is None:
            protein = 0
        if fat is None:
            fat = 0
        if carbs is None:
            carbs = 0
        return {
            "calories": round(float(kcal), 1),
            "protein": round(float(protein), 2),
            "fat": round(float(fat), 2),
            "carbs": round(float(carbs), 2),
        }
    return None


def update_product_kbju(api_key, product_id, kbju):
    """PATCH продукта: calories, protein, fat, carbs."""
    body = json.dumps(kbju).encode("utf-8")
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/products?id=eq.{product_id}",
        data=body,
        headers={
            "apikey": api_key,
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="PATCH",
    )
    with urllib.request.urlopen(req) as resp:
        pass


def main():
    api_key = (
        (sys.argv[1] if len(sys.argv) > 1 else None)
        or __import__("os").environ.get("SUPABASE_SERVICE_ROLE_KEY")
    )
    if not api_key:
        print("Usage: python3 fetch_kbju_openfoodfacts.py SERVICE_ROLE_KEY")
        print("   or: export SUPABASE_SERVICE_ROLE_KEY=...")
        sys.exit(1)

    print("1. Загружаем продукты без КБЖУ...")
    products = fetch_products_missing_kbju(api_key)
    print(f"   Найдено: {len(products)}")

    updated = 0
    not_found = 0
    errors = 0

    for i, p in enumerate(products):
        pid = p["id"]
        # Поиск: сначала en, потом name (ru)
        names = p.get("names") or {}
        search_name = names.get("en") or names.get("ru") or p.get("name") or ""
        if not search_name or len(str(search_name).strip()) < 2:
            not_found += 1
            continue

        kbju = search_openfoodfacts(str(search_name).strip())
        if not kbju:
            not_found += 1
            if (i + 1) % 50 == 0:
                print(f"   [{i+1}/{len(products)}] ...")
            time.sleep(1.5)
            continue

        try:
            update_product_kbju(api_key, pid, kbju)
            updated += 1
            if updated <= 5 or updated % 50 == 0:
                print(f"   OK #{updated}: {search_name[:40]} -> {kbju}")
        except Exception as e:
            errors += 1
            print(f"   ERROR {pid}: {e}")

        time.sleep(1.5)

    print()
    print(f"Готово. Обновлено: {updated}, не найдено в OFF: {not_found}, ошибок: {errors}")


if __name__ == "__main__":
    main()
