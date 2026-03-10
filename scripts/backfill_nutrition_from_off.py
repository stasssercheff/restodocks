#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Backfill КБЖУ и аллергенов для продуктов без калорий из Open Food Facts.

Безопасный режим:
  - dry-run по умолчанию: только показывает, что будет обновлено
  - обновляет только продукты с calories IS NULL или calories = 0
  - пауза 2 сек между запросами к OFF
  - логирование в файл и консоль

Использование:
  python3 scripts/backfill_nutrition_from_off.py              # dry-run
  python3 scripts/backfill_nutrition_from_off.py --apply      # реальное обновление
  python3 scripts/backfill_nutrition_from_off.py --limit 50   # ограничить количество
"""

import json
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional
from datetime import datetime

# ─── Config ─────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
LOG_FILE = os.path.join(REPO_ROOT, "backfill_nutrition.log")

SUPABASE_URL = "https://osglfptwbuqqmqunttha.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE"
# Для PATCH нужен SERVICE_ROLE_KEY (RLS). Задайте: export SUPABASE_SERVICE_KEY=...
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
API_KEY = SERVICE_KEY or ANON_KEY

OFF_BASE = "https://world.openfoodfacts.org"
OFF_TIMEOUT = 25
PAUSE_SEC = 2.0
MAX_SANE_KCAL = 320.0
MIN_SANE_KCAL = 1.0
PAGE_SIZE = 15

SKIP_WORDS = [
    "dried", "сухой", "сушен", "chips", "чипс", "fried", "жарен",
    "oil", "масло", "powder", "порошок", "crisp", "snack", "дегидр",
    "dehydrat", "roasted", "жарен", "toasted",
]

# Упаковка, тара, расходники — не ищем КБЖУ в OFF (подстроки, ловят вариации)
PACKAGING_WORDS = [
    # Бар / газирование
    "баллон", "сифон", "нарзанник", "картридж", "siphon", "cartridge",
    # Диспенсеры, тара
    "диспенсер", "dispenser", "упаковка", "packaging",
    # Пакеты и мешки (непищевые)
    "вакуумный пакет", "мешок для мусора", "мешок мусорн", "крафт-пакет",
    "пакет-майк", "пакет майк", "пакет для мусора",
    # Салфетки, зубочистки, трубочки
    "салфетк", "зубочистк", "трубочк", "палочк для суши", "пик для канапе",
    "napkin", "toothpick", "straw",
    # Соусники, контейнеры
    "соусник", "соусниц", "ланч-бокс", "ланчбокс", "lunch box", "lunchbox",
    "контейнер однораз", "одноразов контейнер",
    # Пленка, фольга, пергамент
    "пищевая пленка", "пленка пищевая", "рукав для запекания", "рукав запекания",
    "cling film", "clingfilm", "stretch film", "foil tray", "baking paper",
    "greaseproof", "пергамент для выпечк", "пергамент выпечк",
    # Кондитерский инвентарь
    "тюльпан", "насадка для мешка", "насадка кондитерск", "насадка для капкейк",
    "кондитерский мешок", "мешок кондитерск", "piping tip",
    "piping bag", "pastry bag", "cupcake liner", "cake box", "корнет",
    "коробка для капкейк", "упаковка для капкейк", "подложка для торта",
    # Одноразовая посуда
    "одноразов стакан", "одноразов тарелк", "одноразов вилк", "одноразов ложк",
    "одноразов прибор", "disposable cup", "disposable plate", "disposable",
    # Доставка
    "коробка для пицц", "упаковка для суши", "крафт пакет", "гофрокороб",
    "гофроупаковк",
    # Кухня
    "поддон", "подложка", "лоток", "поднос", "крышка для контейнер", "tray",
    # Персонал
    "перчатк", "шапочк поварск", "сетк для волос", "маск",
    "glove", "chef cap", "hair net",
]


def log(msg: str, also_print: bool = True) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    if also_print:
        print(line)


def parse_num(v) -> Optional[float]:
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v)
        except ValueError:
            return None
    return None


def should_skip(name: str) -> bool:
    n = (name or "").lower()
    return any(w in n for w in SKIP_WORDS)


def is_packaging(product: dict) -> bool:
    """Упаковка/тара/расходник — не ищем КБЖУ."""
    texts = []
    names = product.get("names")
    if isinstance(names, dict):
        texts.extend([names.get("ru") or "", names.get("en") or ""])
    texts.append(product.get("name") or "")
    combined = " ".join(t for t in texts if t).lower()
    return any(w in combined for w in PACKAGING_WORDS)


def match_score(search: str, product_name: str, kcal: float) -> float:
    s = search.lower()
    p = product_name.lower()
    words = [w for w in s.split() if len(w) > 1]
    score = 0
    for w in words:
        if w in p:
            score += 2
    if words:
        score /= len(words)
    if p.startswith(s) or s.startswith(p):
        score += 3
    return score


def sane_calories(name: str, raw: Optional[float]) -> Optional[float]:
    if raw is None:
        return None
    n = (name or "").lower()
    if "грудка" in n or "филе" in n or "chicken" in n or "куриц" in n:
        if raw < 50:
            return 165.0
    if "масло" in n or "oil" in n or "орех" in n or "nut" in n:
        return raw
    if "авокадо" in n or "avocado" in n:
        if raw > 220:
            return 160.0
    if raw > MAX_SANE_KCAL:
        return MAX_SANE_KCAL
    if raw < MIN_SANE_KCAL:
        return None
    return raw


def fetch_off(search_term: str) -> Optional[dict]:
    """Поиск в Open Food Facts. Возвращает лучший матч или None."""
    if not (search_term or "").strip():
        return None
    query = urllib.parse.quote(search_term.strip())
    url = f"{OFF_BASE}/cgi/search.pl?search_terms={query}&search_simple=1&action=process&json=1&page_size={PAGE_SIZE}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Restodocks-backfill/1.0"})
        with urllib.request.urlopen(req, timeout=OFF_TIMEOUT) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, socket.timeout, OSError) as e:
        log(f"  OFF error: {type(e).__name__}: {e}")
        return None

    products = data.get("products") or []
    search_lower = search_term.lower()
    best = None
    best_score = -1

    for p in products:
        if not isinstance(p, dict):
            continue
        name = (p.get("product_name") or p.get("product_name_ru") or "").lower()
        if should_skip(name):
            continue
        nut = p.get("nutriments")
        if not nut:
            continue

        kcal = parse_num(nut.get("energy-kcal_100g"))
        if kcal is None:
            kj = parse_num(nut.get("energy_100g"))
            if kj is not None:
                kcal = kj / 4.184
        protein = parse_num(nut.get("proteins_100g"))
        fat = parse_num(nut.get("fat_100g"))
        carbs = parse_num(nut.get("carbohydrates_100g"))

        if kcal is None and protein is None and fat is None and carbs is None:
            continue

        if kcal is not None and (kcal < MIN_SANE_KCAL or kcal > MAX_SANE_KCAL):
            continue

        kcal_sane = sane_calories(search_term, kcal)
        if kcal_sane is None and kcal is not None:
            continue

        score = match_score(search_lower, name, kcal or 0)
        if score > best_score:
            best_score = score
            tags = p.get("allergens_tags") or []
            if isinstance(tags, list):
                tags = [str(t) for t in tags]
            else:
                tags = []
            cg = any("gluten" in t or "wheat" in t or "cereals" in t for t in tags)
            cl = any("milk" in t or "lactose" in t for t in tags)
            best = {
                "calories": kcal_sane or kcal,
                "protein": protein or 0,
                "fat": fat or 0,
                "carbs": carbs or 0,
                "contains_gluten": bool(cg) if tags else None,
                "contains_lactose": bool(cl) if tags else None,
            }
    return best


def fetch_products_without_nutrition():
    """Получить продукты из Supabase с пустыми калориями."""
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
        except urllib.error.HTTPError as e:
            log(f"Supabase fetch error {e.code}: {e.read().decode()[:200]}")
            break
        if not batch:
            break
        products.extend(batch)
        if len(batch) < 500:
            break
        offset += 500
    return products


def update_product(product_id: str, data: dict) -> bool:
    """Обновить продукт в Supabase."""
    body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/products?id=eq.{product_id}",
        data=body,
        headers={
            "apikey": API_KEY,
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
        method="PATCH",
    )
    try:
        with urllib.request.urlopen(req, timeout=30):
            return True
    except urllib.error.HTTPError as e:
        log(f"  Update error {e.code}: {e.read().decode()[:200]}")
        return False


def search_terms_for(product: dict):
    """Варианты поиска: основной + укороченные. Убираем VND и др."""
    names = product.get("names")
    bases = []
    if isinstance(names, dict):
        ru = (names.get("ru") or names.get("en") or "").strip()
        en = (names.get("en") or names.get("ru") or "").strip()
        if ru and ru not in bases:
            bases.append(ru)
        if en and en != ru and en not in bases:
            bases.append(en)
    name = (product.get("name") or "").strip()
    if name and name not in bases:
        bases.append(name)
    out = []
    for b in bases:
        for junk in ("VND", "THB", "RUB", "USD", "EUR"):
            b = b.replace(junk, " ")
        cleaned = " ".join(b.split()).strip()
        if cleaned and cleaned not in out:
            out.append(cleaned)
    # Добавляем укороченные: "Almond extract" -> "Almond", "Baking soda" -> "soda"
    extras = []
    for t in out:
        words = t.split()
        if len(words) >= 2:
            # Первое слово часто главное: "Almond extract" -> "Almond"
            extras.append(words[0])
            # Без последнего модификатора: extract, powder, salt...
            mods = {"extract", "powder", "salt", "soda", "acid", "bitters", "экстракт", "порошок", "соль", "кислота"}
            if words[-1].lower() in mods and len(words) > 1:
                extras.append(" ".join(words[:-1]))
    for e in extras:
        if e and len(e) > 2 and e not in out:
            out.append(e)
    return out


def main() -> None:
    args = sys.argv[1:]
    dry_run = "--apply" not in args
    limit = None
    for i, a in enumerate(args):
        if a == "--limit" and i + 1 < len(args):
            try:
                limit = int(args[i + 1])
            except ValueError:
                pass
            break

    log("=" * 60)
    log("Backfill nutrition from Open Food Facts")
    log(f"Mode: {'DRY-RUN (no changes)' if dry_run else 'APPLY (will update DB)'}")
    if limit:
        log(f"Limit: {limit} products")
    log("")

    products = fetch_products_without_nutrition()
    log(f"Products without nutrition: {len(products)}")
    if not products:
        log("Nothing to do.")
        return

    if limit:
        products = products[:limit]
        log(f"Processing first {limit} products")

    updated = 0
    not_found = 0
    errors = 0
    skipped = 0
    total = len(products)
    progress_interval = 25  # сводка каждые N продуктов

    for i, p in enumerate(products):
        pid = p.get("id")
        name = p.get("name") or ""
        if is_packaging(p):
            skipped += 1
            log(f"[{i+1}/{total}] Skip (упаковка): {name[:40] or pid}")
            continue
        search_variants = search_terms_for(p)
        if not search_variants:
            skipped += 1
            log(f"[{i+1}/{total}] Skip (no name): {name or pid}")
            continue

        pct = int(100 * (i + 1) / total)
        result = None
        for search in search_variants:
            result = fetch_off(search)
            time.sleep(PAUSE_SEC)
            if result is not None:
                break

        if result is None:
            not_found += 1
            log(f"[{i+1}/{total}] ({pct}%) {name[:35]:<35} | Не найдено")
            continue

        # Не сохраняем мусор: калории пусто и БЖУ все нули
        cal = result.get("calories")
        pr = result.get("protein", 0) or 0
        fa = result.get("fat", 0) or 0
        ca = result.get("carbs", 0) or 0
        if cal is None and pr == 0 and fa == 0 and ca == 0:
            not_found += 1
            log(f"[{i+1}/{total}] ({pct}%) {name[:35]:<35} | Пропуск (пустой результат)")
            continue

        payload = {
            "calories": result["calories"],
            "protein": result["protein"],
            "fat": result["fat"],
            "carbs": result["carbs"],
        }
        if result.get("contains_gluten") is not None:
            payload["contains_gluten"] = result["contains_gluten"]
        if result.get("contains_lactose") is not None:
            payload["contains_lactose"] = result["contains_lactose"]

        cal_str = str(round(cal)) if cal is not None else "?"
        log(f"[{i+1}/{total}] ({pct}%) {name[:35]:<35} | OK {cal_str} ккал Б:{pr} Ж:{fa} У:{ca}")

        if dry_run:
            updated += 1
            continue

        if update_product(pid, payload):
            updated += 1
        else:
            errors += 1

        # Периодическая сводка
        if (i + 1) % progress_interval == 0:
            log("")
            log(f"  >>> Прогресс: {i+1}/{total} | Обновлено: {updated} | Не найдено: {not_found} | Ошибки: {errors}")
            log("")

    log("")
    log("=" * 50)
    log("ИТОГО:")
    log(f"  Обновлено:    {updated}")
    log(f"  Не найдено:   {not_found}")
    log(f"  Ошибки:       {errors}")
    log(f"  Пропущено:    {skipped}")
    log(f"Log: {LOG_FILE}")


if __name__ == "__main__":
    main()
