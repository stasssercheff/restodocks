#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Backfill КБЖУ и аллергенов для продуктов без калорий.

Каскад источников (по очереди для каждого продукта):
  1. Open Food Facts (всегда)
  2. USDA FoodData Central (если USDA_API_KEY задан)
  3. FatSecret (если FATSECRET_CLIENT_ID и FATSECRET_CLIENT_SECRET заданы)
  4. Правила по категориям (молоко, сливки, алкоголь, вода и т.п.)
  5. AI (ai-refine-nutrition) — fallback для «Не найдено». Требует настроенные ключи в Supabase (GIGACHAT, OPENAI и т.п.)

Использование:
  export SUPABASE_SERVICE_KEY='ключ_из_supabase'
  # ключ вставлять БЕЗ своих кавычек, только между кавычками команды
  export USDA_API_KEY=...                    # опционально
  export FATSECRET_CLIENT_ID=...             # опционально
  export FATSECRET_CLIENT_SECRET=...

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
# Для PATCH нужен service_role. Задайте: export SUPABASE_SERVICE_KEY='ключ' (ключ без кавычек)
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
API_KEY = SERVICE_KEY or ANON_KEY
# При 401: проверь что SUPABASE_SERVICE_KEY задан и относится к проекту osglfptwbuqqmqunttha

OFF_BASE = "https://world.openfoodfacts.org"
USDA_BASE = "https://api.nal.usda.gov/fdc/v1"
FATSECRET_TOKEN_URL = "https://oauth.fatsecret.com/connect/token"
FATSECRET_API_URL = "https://platform.fatsecret.com/rest/server.api"
OFF_TIMEOUT = 25
PAUSE_SEC = 2.0
OFF_RETRIES = 3  # retry при timeout / network unreachable

USDA_API_KEY = os.environ.get("USDA_API_KEY")
FATSECRET_CLIENT_ID = os.environ.get("FATSECRET_CLIENT_ID")
FATSECRET_CLIENT_SECRET = os.environ.get("FATSECRET_CLIENT_SECRET")
_fatsecret_token = None
_fatsecret_token_expires = 0
MAX_SANE_KCAL = 320.0
MIN_SANE_KCAL = 1.0
PAGE_SIZE = 15

SKIP_WORDS = [
    "dried", "сухой", "сушен", "chips", "чипс", "fried", "жарен",
    "oil", "масло", "powder", "порошок", "crisp", "snack", "дегидр",
    "dehydrat", "roasted", "жарен", "toasted",
]

# Правила по категориям: когда API не нашёл — подставляем типичные КБЖУ.
# (список подстрок, которые должны ВСЕ быть в названии; nutrition dict)
# Подстроки проверяются в lower() названия. КБЖУ на 100 г.
CATEGORY_RULES = [
    # Молоко
    (["молоко", "3.2"], {"calories": 60, "protein": 2.8, "fat": 3.2, "carbs": 4.7, "contains_gluten": None, "contains_lactose": True}),
    (["молоко", "3,2"], {"calories": 60, "protein": 2.8, "fat": 3.2, "carbs": 4.7, "contains_gluten": None, "contains_lactose": True}),
    (["молоко", "2.5"], {"calories": 52, "protein": 2.8, "fat": 2.5, "carbs": 4.7, "contains_gluten": None, "contains_lactose": True}),
    (["молоко", "1.5"], {"calories": 44, "protein": 2.8, "fat": 1.5, "carbs": 4.7, "contains_gluten": None, "contains_lactose": True}),
    (["milk", "3.2"], {"calories": 60, "protein": 2.8, "fat": 3.2, "carbs": 4.7, "contains_gluten": None, "contains_lactose": True}),
    # Сливки
    (["сливки", "33"], {"calories": 322, "protein": 2.2, "fat": 33, "carbs": 3.6, "contains_gluten": None, "contains_lactose": True}),
    (["сливки", "20"], {"calories": 206, "protein": 2.5, "fat": 20, "carbs": 3.2, "contains_gluten": None, "contains_lactose": True}),
    (["сливки", "10"], {"calories": 119, "protein": 2.5, "fat": 10, "carbs": 3.6, "contains_gluten": None, "contains_lactose": True}),
    (["cream", "33"], {"calories": 322, "protein": 2.2, "fat": 33, "carbs": 3.6, "contains_gluten": None, "contains_lactose": True}),
    # Сметана
    (["сметана", "20"], {"calories": 206, "protein": 2.5, "fat": 20, "carbs": 3.2, "contains_gluten": None, "contains_lactose": True}),
    (["сметана", "15"], {"calories": 162, "protein": 2.6, "fat": 15, "carbs": 3.0, "contains_gluten": None, "contains_lactose": True}),
    (["сметана", "10"], {"calories": 116, "protein": 2.7, "fat": 10, "carbs": 2.9, "contains_gluten": None, "contains_lactose": True}),
    # Кефир
    (["кефир", "2.5"], {"calories": 53, "protein": 2.9, "fat": 2.5, "carbs": 4.0, "contains_gluten": None, "contains_lactose": True}),
    (["кефир", "1"], {"calories": 40, "protein": 2.8, "fat": 1.0, "carbs": 4.0, "contains_gluten": None, "contains_lactose": True}),
    # Масло сливочное
    (["масло", "сливоч", "82.5"], {"calories": 748, "protein": 0.5, "fat": 82.5, "carbs": 0.8, "contains_gluten": None, "contains_lactose": True}),
    (["масло", "сливоч"], {"calories": 748, "protein": 0.5, "fat": 82.5, "carbs": 0.8, "contains_gluten": None, "contains_lactose": True}),
    (["butter"], {"calories": 748, "protein": 0.5, "fat": 82.5, "carbs": 0.8, "contains_gluten": None, "contains_lactose": True}),
    # Сахар
    (["сахар", "песок"], {"calories": 398, "protein": 0, "fat": 0, "carbs": 99.7, "contains_gluten": False, "contains_lactose": False}),
    (["сахар", "рафинад"], {"calories": 398, "protein": 0, "fat": 0, "carbs": 99.7, "contains_gluten": False, "contains_lactose": False}),
    (["sugar"], {"calories": 398, "protein": 0, "fat": 0, "carbs": 99.7, "contains_gluten": False, "contains_lactose": False}),
    # Соль
    (["соль", "поварен"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["соль", "йодирован"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["salt"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    # Вода (питьевая, без калорий)
    (["вода", "питьев"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["water"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    # Грибы
    (["шампиньон"], {"calories": 27, "protein": 4.3, "fat": 1.0, "carbs": 0.1, "contains_gluten": False, "contains_lactose": False}),
    (["шиитаке"], {"calories": 34, "protein": 2.2, "fat": 0.5, "carbs": 6.8, "contains_gluten": False, "contains_lactose": False}),
    (["энокитаке"], {"calories": 37, "protein": 2.7, "fat": 0.3, "carbs": 7.8, "contains_gluten": False, "contains_lactose": False}),
    (["эринги"], {"calories": 37, "protein": 3.1, "fat": 0.4, "carbs": 6.9, "contains_gluten": False, "contains_lactose": False}),
    (["вешенк"], {"calories": 33, "protein": 3.3, "fat": 0.4, "carbs": 6.1, "contains_gluten": False, "contains_lactose": False}),
    # Овощи и зелень
    (["мокровь"], {"calories": 41, "protein": 0.9, "fat": 0.2, "carbs": 9.6, "contains_gluten": False, "contains_lactose": False}),  # опечатка: морковь
    (["купуста", "б/к"], {"calories": 27, "protein": 1.8, "fat": 0.1, "carbs": 5.4, "contains_gluten": False, "contains_lactose": False}),  # белокочанная
    (["купуста", "к/к"], {"calories": 31, "protein": 1.4, "fat": 0.2, "carbs": 7.4, "contains_gluten": False, "contains_lactose": False}),  # краснокочанная
    (["шпинат"], {"calories": 23, "protein": 2.9, "fat": 0.4, "carbs": 3.6, "contains_gluten": False, "contains_lactose": False}),
    (["щавель"], {"calories": 22, "protein": 2.0, "fat": 0.7, "carbs": 3.2, "contains_gluten": False, "contains_lactose": False}),
    (["эндивий"], {"calories": 17, "protein": 1.3, "fat": 0.2, "carbs": 3.4, "contains_gluten": False, "contains_lactose": False}),
    (["spinach"], {"calories": 23, "protein": 2.9, "fat": 0.4, "carbs": 3.6, "contains_gluten": False, "contains_lactose": False}),
    # Фрукты
    (["черешн"], {"calories": 52, "protein": 1.1, "fat": 0.2, "carbs": 12.2, "contains_gluten": False, "contains_lactose": False}),
    (["яблоко", "красн"], {"calories": 52, "protein": 0.3, "fat": 0.2, "carbs": 13.6, "contains_gluten": False, "contains_lactose": False}),
    # Шоколад
    (["шоколад", "белый"], {"calories": 539, "protein": 5.9, "fat": 32.1, "carbs": 59.2, "contains_gluten": False, "contains_lactose": True}),
    (["шоколад", "молочн"], {"calories": 535, "protein": 7.7, "fat": 29.7, "carbs": 59.4, "contains_gluten": False, "contains_lactose": True}),
    (["шоколад", "темн"], {"calories": 546, "protein": 4.9, "fat": 31.3, "carbs": 61.2, "contains_gluten": False, "contains_lactose": False}),
    (["шоколад", "горьк"], {"calories": 546, "protein": 4.9, "fat": 31.3, "carbs": 61.2, "contains_gluten": False, "contains_lactose": False}),
    (["шоколад", "рубинов"], {"calories": 540, "protein": 5.0, "fat": 32.0, "carbs": 60.0, "contains_gluten": False, "contains_lactose": False}),
    (["шоколадные", "капл"], {"calories": 540, "protein": 5.0, "fat": 32.0, "carbs": 60.0, "contains_gluten": False, "contains_lactose": True}),
    (["chocolate", "dark"], {"calories": 546, "protein": 4.9, "fat": 31.3, "carbs": 61.2, "contains_gluten": False, "contains_lactose": False}),
    # Специи и травы
    (["шалфей"], {"calories": 315, "protein": 10.6, "fat": 12.8, "carbs": 60.7, "contains_gluten": False, "contains_lactose": False}),
    (["шафран"], {"calories": 310, "protein": 11.4, "fat": 5.9, "carbs": 65.4, "contains_gluten": False, "contains_lactose": False}),
    (["хмели", "сунели"], {"calories": 270, "protein": 10.0, "fat": 5.0, "carbs": 50.0, "contains_gluten": False, "contains_lactose": False}),
    # Мясо и птица
    (["шейка", "курин"], {"calories": 158, "protein": 16.8, "fat": 10.0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["щека", "говяж"], {"calories": 154, "protein": 21.4, "fat": 7.0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["щека", "свин"], {"calories": 267, "protein": 12.8, "fat": 24.1, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    # Рыба
    (["щука"], {"calories": 84, "protein": 18.4, "fat": 0.8, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["шпрот"], {"calories": 363, "protein": 17.4, "fat": 32.4, "carbs": 0.4, "contains_gluten": False, "contains_lactose": False}),
    # Колбасы и мясопродукты
    (["чоризо"], {"calories": 455, "protein": 24.1, "fat": 38.3, "carbs": 1.9, "contains_gluten": False, "contains_lactose": False}),
    (["chorizo"], {"calories": 455, "protein": 24.1, "fat": 38.3, "carbs": 1.9, "contains_gluten": False, "contains_lactose": False}),
    # Бобовые
    (["эдамаме"], {"calories": 122, "protein": 10.9, "fat": 5.2, "carbs": 9.9, "contains_gluten": False, "contains_lactose": False}),
    (["edamame"], {"calories": 122, "protein": 10.9, "fat": 5.2, "carbs": 9.9, "contains_gluten": False, "contains_lactose": False}),
    # Снэки
    (["чипсы", "картофел"], {"calories": 536, "protein": 7.0, "fat": 35.0, "carbs": 49.0, "contains_gluten": False, "contains_lactose": False}),
    # Подсластители
    (["эритрит"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["erythritol"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    # Яйца
    (["яйцо", "вес"], {"calories": 155, "protein": 12.6, "fat": 10.6, "carbs": 1.1, "contains_gluten": False, "contains_lactose": False}),
    # Кокос
    (["кокос", "мякоть"], {"calories": 354, "protein": 3.3, "fat": 33.5, "carbs": 15.2, "contains_gluten": False, "contains_lactose": False}),
    (["комбу"], {"calories": 43, "protein": 1.0, "fat": 0.6, "carbs": 9.6, "contains_gluten": False, "contains_lactose": False}),
    # Колбаса охотничья, куленова
    (["колбаса", "охотнич"], {"calories": 380, "protein": 25.0, "fat": 30.0, "carbs": 2.0, "contains_gluten": False, "contains_lactose": False}),
    (["куленова"], {"calories": 380, "protein": 25.0, "fat": 30.0, "carbs": 2.0, "contains_gluten": False, "contains_lactose": False}),
    # Соль, добавки
    (["флёр", "де", "сель"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["хлорид", "кальция"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    # Соки (юзу)
    (["юзу", "сок"], {"calories": 32, "protein": 0.5, "fat": 0.1, "carbs": 7.0, "contains_gluten": False, "contains_lactose": False}),
    # Алкоголь — типичные ккал/100г (крепость ~40% = ~231, вино ~80, пиво ~43)
    (["водка"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["виски"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["вино", "бел"], {"calories": 82, "protein": 0, "fat": 0, "carbs": 3.5, "contains_gluten": False, "contains_lactose": False}),
    (["вино", "красн"], {"calories": 83, "protein": 0, "fat": 0, "carbs": 3.7, "contains_gluten": False, "contains_lactose": False}),
    (["вино"], {"calories": 80, "protein": 0, "fat": 0, "carbs": 3.5, "contains_gluten": False, "contains_lactose": False}),
    (["вино", "розов"], {"calories": 75, "protein": 0, "fat": 0, "carbs": 2.0, "contains_gluten": False, "contains_lactose": False}),
    (["пиво"], {"calories": 43, "protein": 0.5, "fat": 0, "carbs": 3.6, "contains_gluten": True, "contains_lactose": False}),
    (["текила"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["ром"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["джин"], {"calories": 263, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["коньяк"], {"calories": 239, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["ликер"], {"calories": 320, "protein": 0, "fat": 0, "carbs": 40, "contains_gluten": False, "contains_lactose": False}),
    (["ликёр"], {"calories": 320, "protein": 0, "fat": 0, "carbs": 40, "contains_gluten": False, "contains_lactose": False}),
    (["просекко"], {"calories": 80, "protein": 0, "fat": 0, "carbs": 4.0, "contains_gluten": False, "contains_lactose": False}),
    (["шампан"], {"calories": 80, "protein": 0, "fat": 0, "carbs": 3.5, "contains_gluten": False, "contains_lactose": False}),
    (["игрист"], {"calories": 80, "protein": 0, "fat": 0, "carbs": 3.5, "contains_gluten": False, "contains_lactose": False}),
    (["абсент"], {"calories": 264, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["вермут"], {"calories": 140, "protein": 0, "fat": 0, "carbs": 15, "contains_gluten": False, "contains_lactose": False}),
    (["сидр"], {"calories": 47, "protein": 0, "fat": 0, "carbs": 4.3, "contains_gluten": False, "contains_lactose": False}),
    (["саке"], {"calories": 134, "protein": 0.5, "fat": 0, "carbs": 5.0, "contains_gluten": False, "contains_lactose": False}),
    # «Т.» — префикс барных продуктов (типовые)
    (["т.", "водка"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "вино"], {"calories": 80, "protein": 0, "fat": 0, "carbs": 3.5, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "виски"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "пиво"], {"calories": 43, "protein": 0.5, "fat": 0, "carbs": 3.6, "contains_gluten": True, "contains_lactose": False}),
    (["т.", "текила"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "ром"], {"calories": 231, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "джин"], {"calories": 263, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "коньяк"], {"calories": 239, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "ликер"], {"calories": 320, "protein": 0, "fat": 0, "carbs": 40, "contains_gluten": False, "contains_lactose": False}),
    (["т.", "ликёр"], {"calories": 320, "protein": 0, "fat": 0, "carbs": 40, "contains_gluten": False, "contains_lactose": False}),
    # Напитки без калорий
    (["кока-кола", "zero"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["кола", "zero"], {"calories": 0, "protein": 0, "fat": 0, "carbs": 0, "contains_gluten": False, "contains_lactose": False}),
    (["тоник"], {"calories": 34, "protein": 0, "fat": 0, "carbs": 8.4, "contains_gluten": False, "contains_lactose": False}),
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
    """Поиск в Open Food Facts. Возвращает лучший матч или None. Retry при timeout / network."""
    if not (search_term or "").strip():
        return None
    query = urllib.parse.quote(search_term.strip())
    url = f"{OFF_BASE}/cgi/search.pl?search_terms={query}&search_simple=1&action=process&json=1&page_size={PAGE_SIZE}"
    last_err = None
    for attempt in range(OFF_RETRIES):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Restodocks-backfill/1.0"})
            with urllib.request.urlopen(req, timeout=OFF_TIMEOUT) as resp:
                data = json.loads(resp.read().decode())
            last_err = None
            break
        except (urllib.error.URLError, TimeoutError, socket.timeout, OSError, ConnectionError) as e:
            last_err = e
            log(f"  OFF error: {type(e).__name__}: {e}")
            if attempt < OFF_RETRIES - 1:
                delay = PAUSE_SEC * (2 ** attempt)
                log(f"  Retry через {delay:.0f}s ({attempt + 2}/{OFF_RETRIES})")
                time.sleep(delay)
            else:
                return None
        except json.JSONDecodeError as e:
            log(f"  OFF error: {type(e).__name__}: {e}")
            return None

    if last_err is not None:
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


def _get_fatsecret_token() -> Optional[str]:
    """Получить OAuth2 токен FatSecret (кешируется)."""
    global _fatsecret_token, _fatsecret_token_expires
    if not FATSECRET_CLIENT_ID or not FATSECRET_CLIENT_SECRET:
        return None
    now = time.time()
    if _fatsecret_token and _fatsecret_token_expires > now + 300:
        return _fatsecret_token
    import base64
    auth = base64.b64encode(
        f"{FATSECRET_CLIENT_ID}:{FATSECRET_CLIENT_SECRET}".encode()
    ).decode()
    data = "grant_type=client_credentials&scope=basic".encode()
    req = urllib.request.Request(
        FATSECRET_TOKEN_URL,
        data=data,
        headers={
            "Authorization": f"Basic {auth}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            j = json.loads(resp.read().decode())
            _fatsecret_token = j.get("access_token")
            _fatsecret_token_expires = now + (j.get("expires_in") or 86400)
            return _fatsecret_token
    except Exception:
        return None


def fetch_usda(search_term: str) -> Optional[dict]:
    """Поиск в USDA FoodData Central. Возвращает calories, protein, fat, carbs или None."""
    if not USDA_API_KEY or not (search_term or "").strip():
        return None
    query = search_term.strip()
    url = f"{USDA_BASE}/foods/search?api_key={urllib.parse.quote(USDA_API_KEY)}"
    body = json.dumps({"query": query, "pageSize": 10}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=OFF_TIMEOUT) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, socket.timeout, OSError):
        return None
    foods = data.get("foods") or []
    search_lower = query.lower()
    best = None
    best_score = -1
    # USDA nutrient IDs: 1008=Energy kcal, 1003=Protein, 1004=Fat, 1005=Carbs
    NUT_MAP = {1008: "calories", 1003: "protein", 1004: "fat", 1005: "carbs"}
    for f in foods:
        name = (f.get("description") or "").lower()
        if should_skip(name):
            continue
        vals = {}
        for n in f.get("foodNutrients") or []:
            nid = n.get("nutrientId")
            if nid in NUT_MAP:
                vals[NUT_MAP[nid]] = parse_num(n.get("value"))
        kcal = vals.get("calories")
        if kcal is not None and (kcal < MIN_SANE_KCAL or kcal > MAX_SANE_KCAL):
            continue
        if not vals:
            continue
        score = match_score(search_lower, name, kcal or 0)
        if score > best_score:
            best_score = score
            pr = vals.get("protein") or 0
            fa = vals.get("fat") or 0
            ca = vals.get("carbs") or 0
            cal = kcal
            if cal is None and (pr or fa or ca):
                cal = 4 * pr + 9 * fa + 4 * ca
            best = {
                "calories": cal,
                "protein": pr,
                "fat": fa,
                "carbs": ca,
                "contains_gluten": None,
                "contains_lactose": None,
            }
    return best


def fetch_fatsecret(search_term: str) -> Optional[dict]:
    """Поиск в FatSecret. Возвращает calories, protein, fat, carbs или None."""
    token = _get_fatsecret_token()
    if not token or not (search_term or "").strip():
        return None
    params = urllib.parse.urlencode({
        "method": "foods.search",
        "search_expression": search_term.strip(),
        "max_results": 10,
        "format": "json",
    })
    req = urllib.request.Request(
        f"{FATSECRET_API_URL}?{params}",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=OFF_TIMEOUT) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, socket.timeout, OSError):
        return None
    foods_obj = data.get("foods") or {}
    food_list = foods_obj.get("food")
    if not food_list:
        return None
    if not isinstance(food_list, list):
        food_list = [food_list]
    search_lower = search_term.lower()
    best = None
    best_score = -1
    import re
    def _parse_fs_desc(desc: str):
        """Парсим 'Per 100g - Calories: 22kcal | Fat: 0.34g | Carbs: 3.28g | Protein: 3.09g'"""
        if "Per 100g" not in desc and "per 100g" not in desc.lower():
            return None
        kcal = re.search(r"Calories:\s*([\d.]+)\s*kcal", desc, re.I)
        fat = re.search(r"Fat:\s*([\d.]+)\s*g", desc, re.I)
        carbs = re.search(r"Carbs:\s*([\d.]+)\s*g", desc, re.I)
        protein = re.search(r"Protein:\s*([\d.]+)\s*g", desc, re.I)
        if not (kcal and fat and carbs and protein):
            return None
        return (
            parse_num(kcal.group(1)),
            parse_num(fat.group(1)),
            parse_num(carbs.group(1)),
            parse_num(protein.group(1)),
        )
    for fo in food_list:
        desc = (fo.get("food_description") or "")
        name = (fo.get("food_name") or "").lower()
        if should_skip(name):
            continue
        parsed = _parse_fs_desc(desc)
        if not parsed:
            continue
        kcal, fat, carbs, protein = parsed
        if kcal is not None and (kcal < MIN_SANE_KCAL or kcal > MAX_SANE_KCAL):
            continue
        if kcal is None and protein is None and fat is None and carbs is None:
            continue
        score = match_score(search_lower, name, kcal or 0)
        if score > best_score:
            best_score = score
            best = {
                "calories": kcal,
                "protein": protein or 0,
                "fat": fat or 0,
                "carbs": carbs or 0,
                "contains_gluten": None,
                "contains_lactose": None,
            }
    return best


def fetch_ai_refine_nutrition(product_name: str) -> Optional[dict]:
    """AI fallback: Edge Function ai-refine-nutrition. Оценка КБЖУ по названию."""
    if not (product_name or "").strip():
        return None
    url = f"{SUPABASE_URL}/functions/v1/ai-refine-nutrition"
    body = json.dumps({"productName": product_name.strip()}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}",
            "apikey": API_KEY,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300]
        log(f"  AI error {e.code}: {body}")
        return None
    except (urllib.error.URLError, TimeoutError, socket.timeout, OSError, json.JSONDecodeError) as e:
        log(f"  AI error: {type(e).__name__}: {e}")
        return None

    if isinstance(data, dict) and "error" in data:
        log(f"  AI error: {data.get('error', data)}")
        return None
    cal = parse_num(data.get("calories"))
    pr = parse_num(data.get("protein"))
    fa = parse_num(data.get("fat"))
    ca = parse_num(data.get("carbs"))
    if cal is None and pr is None and fa is None and ca is None:
        return None
    if cal is not None and (cal < MIN_SANE_KCAL or cal > MAX_SANE_KCAL):
        return None
    return {
        "calories": cal,
        "protein": pr or 0,
        "fat": fa or 0,
        "carbs": ca or 0,
        "contains_gluten": None,
        "contains_lactose": None,
    }


def _product_text_for_rules(product: dict) -> str:
    """Объединённый текст названий для сопоставления с правилами."""
    texts = []
    names = product.get("names")
    if isinstance(names, dict):
        texts.extend([names.get("ru") or "", names.get("en") or ""])
    texts.append(product.get("name") or "")
    return " ".join(t for t in texts if t).lower()


def apply_category_rules(product: dict) -> Optional[dict]:
    """Если API не нашёл — применить правила по категориям. Возвращает nutrition dict или None."""
    text = _product_text_for_rules(product)
    if not text:
        return None
    for keywords, nutrition in CATEGORY_RULES:
        if all(kw in text for kw in keywords):
            return dict(nutrition)
    return None


def fetch_nutrition_cascade(search_term: str) -> Optional[dict]:
    """Каскад: OFF → USDA → FatSecret. Возвращает первый успешный результат."""
    result = fetch_off(search_term)
    if result is not None:
        return result
    time.sleep(PAUSE_SEC * 0.5)
    result = fetch_usda(search_term)
    if result is not None:
        return result
    time.sleep(PAUSE_SEC * 0.5)
    result = fetch_fatsecret(search_term)
    return result


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
        except (urllib.error.URLError, OSError, ConnectionError) as e:
            log(f"Network error fetching products: {e}")
            break
        if not batch:
            break
        products.extend(batch)
        if len(batch) < 500:
            break
        offset += 500
    return products


def update_product(product_id: str, data: dict, retries: int = 3) -> bool:
    """Обновить продукт в Supabase. При сетевой ошибке — retry с паузой."""
    body = json.dumps(data).encode("utf-8")
    for attempt in range(retries):
        try:
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
            with urllib.request.urlopen(req, timeout=30):
                return True
        except urllib.error.HTTPError as e:
            log(f"  Update error {e.code}: {e.read().decode()[:200]}")
            return False
        except (urllib.error.URLError, OSError, ConnectionError, ConnectionResetError) as e:
            log(f"  Network error (attempt {attempt + 1}/{retries}): {e}")
            if attempt < retries - 1:
                delay = PAUSE_SEC * (2 ** attempt)
                log(f"  Retry через {delay:.0f}s")
                time.sleep(delay)
            else:
                return False
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
    log("Backfill nutrition: OFF → USDA → FatSecret (cascade)")
    log(f"Mode: {'DRY-RUN (no changes)' if dry_run else 'APPLY (will update DB)'}")
    log(f"OFF: on | USDA: {'on' if USDA_API_KEY else 'off'} | FatSecret: {'on' if FATSECRET_CLIENT_ID else 'off'} | AI: on (ai-refine-nutrition)")
    key_type = "service_role" if SERVICE_KEY else "anon (export SUPABASE_SERVICE_KEY for PATCH)"
    log(f"Supabase: {key_type}" + (f" (key len={len(SERVICE_KEY)})" if SERVICE_KEY else ""))
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
    from_rules = 0
    from_ai = 0
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

        try:
            pct = int(100 * (i + 1) / total)
            result = None
            for search in search_variants:
                result = fetch_nutrition_cascade(search)
                time.sleep(PAUSE_SEC)
                if result is not None:
                    break

            # Fallback: правила по категориям (молоко, алкоголь, «Т.» и т.п.)
            if result is None:
                result = apply_category_rules(p)
                if result is not None:
                    from_rules += 1
                    log(f"[{i+1}/{total}] ({pct}%) {name[:35]:<35} | Правило по категории")

            # Fallback: AI (ai-refine-nutrition) — оценка КБЖУ по названию
            if result is None and search_variants:
                time.sleep(PAUSE_SEC * 0.5)
                result = fetch_ai_refine_nutrition(search_variants[0])
                if result is not None:
                    from_ai += 1
                    log(f"[{i+1}/{total}] ({pct}%) {name[:35]:<35} | AI")

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
        except Exception as e:
            log(f"  [{i+1}/{total}] Ошибка: {e}")
            errors += 1

    log("")
    log("=" * 50)
    log("ИТОГО:")
    log(f"  Обновлено:    {updated}")
    log(f"  из них по правилам: {from_rules}")
    log(f"  из них по AI:  {from_ai}")
    log(f"  Не найдено:   {not_found}")
    log(f"  Ошибки:       {errors}")
    log(f"  Пропущено:    {skipped}")
    log(f"Log: {LOG_FILE}")


if __name__ == "__main__":
    main()
