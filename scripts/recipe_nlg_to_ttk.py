#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Рецепты RecipeNLG → JSON в формате TechCardRecognitionResult (Restodocks).

Источники:
  - --sample — встроенные 10 примеров (без загрузки)
  - --csv PATH — полный CSV (Kaggle: saldenisov/recipenlg или paultimothymooney/recipenlg)

Примеры:
  python scripts/recipe_nlg_to_ttk.py --sample
  python scripts/recipe_nlg_to_ttk.py --csv ~/Downloads/full_dataset.csv --limit 100
  python scripts/recipe_nlg_to_ttk.py --csv /path/to/file.csv --limit 1000 --out scripts/fixtures/recipenlg/

Зависимости для --csv: pip install pandas
"""
import argparse
import json
import re
import sys
from pathlib import Path


# ─── Парсинг ingredients из RecipeNLG ─────────────────────────────────────
# Пример: "3.0 bone in pork chops, salt, 2.0 tablespoon vegetable oil"
_UNITS = re.compile(
    r"^(?:(\d+(?:\.\d+)?)\s+)?"
    r"(teaspoon|tablespoon|cup|cups|lb|lbs|oz|g|kg|clove|cloves|stalk|can|cans|slice|slices|piece|pieces)?\s*"
    r"(.+)$",
    re.IGNORECASE
)


def _parse_ingredient(s: str) -> dict:
    """Парсит одну строку ингредиента в {productName, grossGrams?, unit?}."""
    s = s.strip()
    if not s:
        return None
    m = _UNITS.match(s)
    if not m:
        return {"productName": s, "grossGrams": None, "unit": None}
    qty_str, unit, name = m.groups()
    name = (name or "").strip()
    if not name:
        return None
    qty = float(qty_str) if qty_str else None
    unit = (unit or "").strip() or None
    # grossGrams в Restodocks — в граммах; RecipeNLG часто даёт стаканы/ложки
    gross = None
    if qty is not None and unit:
        low = (unit or "").lower()
        if low in ("g", "gram", "grams"): gross = qty
        elif low in ("kg",): gross = qty * 1000
        elif low in ("oz",): gross = qty * 28.35
        elif low in ("lb", "lbs"): gross = qty * 453.6
        else: gross = None  # cup, tablespoon — без конвертации
    elif qty is not None and not unit:
        gross = qty  # часто "3.0 bone in pork chops" = 3 штуки
    return {
        "productName": name,
        "grossGrams": gross,
        "netGrams": None,
        "unit": unit,
        "cookingMethod": None,
        "primaryWastePct": None,
        "cookingLossPct": None,
    }


def _ingredients_from_str(text: str) -> list:
    """Парсит строку ингредиентов, разделённых запятыми."""
    if not text or not isinstance(text, str):
        return []
    out = []
    for part in text.split(","):
        obj = _parse_ingredient(part)
        if obj and obj.get("productName"):
            out.append(obj)
    return out


def _ingredients_from_ner(ner: str) -> list:
    """Если ner — строка с запятыми, используем как имена без количества."""
    if not ner or not isinstance(ner, str):
        return []
    return [{"productName": n.strip(), "grossGrams": None, "netGrams": None, "unit": None,
             "cookingMethod": None, "primaryWastePct": None, "cookingLossPct": None}
            for n in ner.split(",") if n.strip()]


def _tech_text(val):
    if val is None:
        return None
    if isinstance(val, list):
        return " ".join(str(x) for x in val) if val else None
    return str(val) if val else None


def to_ttk_json(recipe: dict, use_ingredients: bool = True) -> dict:
    """
    recipe: {name, title, ingredients, steps, directions, ner, ...}
    Возвращает JSON в формате TechCardRecognitionResult.
    """
    ing_raw = recipe.get("ingredients")
    if isinstance(ing_raw, list):
        ingredients = []
        for s in ing_raw:
            parsed = _parse_ingredient(str(s))
            if parsed and parsed.get("productName"):
                ingredients.append(parsed)
    else:
        ingredients = _ingredients_from_str(ing_raw or "") if use_ingredients else []
    if not ingredients:
        ner = recipe.get("ner")
        if isinstance(ner, list):
            ingredients = [{"productName": n, "grossGrams": None, "netGrams": None, "unit": None,
                           "cookingMethod": None, "primaryWastePct": None, "cookingLossPct": None}
                          for n in ner if n]
        else:
            ingredients = _ingredients_from_ner(ner or "")
    return {
        "dishName": recipe.get("name") or recipe.get("title"),
        "technologyText": _tech_text(recipe.get("steps") or recipe.get("directions") or recipe.get("description")),
        "ingredients": ingredients,
        "isSemiFinished": None,
    }


# ─── Загрузка данных ──────────────────────────────────────────────────────

# Встроенные примеры (формат RecipeNLG) — для тестов без Kaggle
_SAMPLE_RECIPES = [
    {
        "name": "pork chop noodle soup",
        "ingredients": "3.0 bone in pork chops, salt, pepper, 2.0 tablespoon vegetable oil, 2.0 cup chicken broth, 4.0 cup vegetable broth, 1.0 red onion, 4.0 carrots, 2.0 clove garlic",
        "steps": "Season pork chops with salt and pepper. Heat oil in a dutch oven. Add chops and cook 4 minutes per side. Add broth, vegetables, thyme. Simmer 90 minutes. Add pasta.",
        "ner": "bone in pork chops, salt, pepper, vegetable oil, chicken broth, vegetable broth, red onion, carrots, garlic",
    },
    {
        "name": "No-Bake Nut Cookies",
        "ingredients": "1 c. firmly packed brown sugar, 1/2 c. evaporated milk, 1/2 tsp. vanilla, 1/2 c. broken nuts, 2 Tbsp. butter, 3 1/2 c. bite size shredded rice biscuits",
        "steps": "Mix brown sugar, nuts, milk and butter. Stir over medium heat. Boil 5 minutes. Stir in vanilla and cereal. Drop into clusters. Let stand until firm.",
        "ner": "brown sugar, milk, vanilla, nuts, butter, rice biscuits",
    },
    {
        "name": "Greek Salad",
        "ingredients": "2 cucumbers, 4 tomatoes, 1 red onion, 200 g feta cheese, 100 g olives, olive oil, oregano",
        "steps": "Dice cucumbers and tomatoes. Slice onion. Cut feta into cubes. Mix all with olives. Dress with olive oil and oregano.",
        "ner": "cucumbers, tomatoes, red onion, feta cheese, olives, olive oil, oregano",
    },
]


def load_sample(limit: int):
    """Встроенные примеры — работает без Kaggle/HuggingFace."""
    for i, r in enumerate(_SAMPLE_RECIPES):
        if i >= limit:
            break
        yield r


def load_csv(path: str, limit: int):
    try:
        import pandas as pd
    except ImportError:
        print("Установи: pip install pandas")
        sys.exit(1)
    df = pd.read_csv(path, nrows=limit, on_bad_lines="skip")
    # Нормализуем колонки: lite — name/steps, full — title/directions
    for _, row in df.iterrows():
        d = row.to_dict()
        if "title" in d and "name" not in d:
            d["name"] = d.get("title")
        if "directions" in d and "steps" not in d:
            d["steps"] = d.get("directions")
        yield d


def main():
    ap = argparse.ArgumentParser(description="RecipeNLG → TechCardRecognitionResult JSON")
    ap.add_argument("--limit", type=int, default=50, help="Сколько рецептов обработать")
    ap.add_argument("--out", type=str, default="scripts/fixtures/recipenlg", help="Папка для JSON")
    ap.add_argument("--csv", type=str, default=None, help="Путь к полному CSV (Kaggle)")
    ap.add_argument("--sample", action="store_true", help="Использовать встроенные примеры (без загрузки)")
    ap.add_argument("--single", action="store_true", help="Один JSON со всеми рецептами (list)")
    args = ap.parse_args()

    if args.csv:
        recipes = list(load_csv(args.csv, args.limit))
    elif args.sample:
        recipes = list(load_sample(min(args.limit, len(_SAMPLE_RECIPES))))
    else:
        print("Укажи --sample (встроенные примеры) или --csv /path/to/full_dataset.csv")
        print("Kaggle: https://www.kaggle.com/datasets/saldenisov/recipenlg")
        sys.exit(1)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    results = [to_ttk_json(r) for r in recipes]

    if args.single:
        out_path = out_dir / "ttk_samples.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"Сохранено {len(results)} рецептов в {out_path}")
    else:
        for i, obj in enumerate(results):
            out_path = out_dir / f"ttk_{i:04d}.json"
            with open(out_path, "w", encoding="utf-8") as f:
                json.dump(obj, f, ensure_ascii=False, indent=2)
        print(f"Сохранено {len(results)} рецептов в {out_dir}/")


if __name__ == "__main__":
    main()
