#!/usr/bin/env python3
"""
Предзаполнение translation_cache переводами названий продуктов (RU/EN/ES -> TR).
Использует бесплатный MyMemory API — не тратит лимиты DeepL.

Результат: SQL-файл для выполнения в Supabase SQL Editor.
После этого Edge Functions (translate-text, auto-translate-product) будут
брать переводы из кэша и не вызывать DeepL для этих продуктов.

Запуск:
  cd restodocks_flutter
  pip install deep-translator  # если ещё нет
  python3 scripts/seed_translation_cache_products.py

Затем: Supabase Dashboard → SQL Editor → вставить содержимое seed_translation_cache.sql
"""
import json
import time
from pathlib import Path

try:
    from deep_translator import MyMemoryTranslator
except ImportError:
    print("Установите: pip install deep-translator")
    exit(1)

# Маппинг языков для MyMemory (ISO 639-1)
LANG_MAP = {"ru": "ru", "en": "en", "es": "es", "tr": "tr"}

# EN->RU, EN->ES — для world_products. Загружаем из upload_missing_products если доступен
def _load_dicts(root: Path):
    en_ru, en_es = {}, {}
    um_path = root / "upload_missing_products.py"
    if um_path.exists():
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("um", um_path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            en_ru = getattr(mod, "EN_RU", {})
            en_es = getattr(mod, "EN_ES", {})
        except Exception as e:
            print(f"  (upload_missing_products не загружен: {e})")
    # Минимальный fallback
    if not en_ru:
        en_ru = {"Tomato": "Томат", "Potato": "Картофель", "Milk": "Молоко", "Egg": "Яйцо"}
    if not en_es:
        en_es = {"Tomato": "Tomate", "Potato": "Patata", "Milk": "Leche", "Egg": "Huevo"}
    return en_ru, en_es


def translate_one(text: str, source: str, target: str) -> str | None:
    """Перевести текст через MyMemory (бесплатно)."""
    if not text or not text.strip():
        return None
    src = LANG_MAP.get(source, source)
    tgt = LANG_MAP.get(target, target)
    if src == tgt:
        return text
    try:
        t = MyMemoryTranslator(source=src, target=tgt)
        return t.translate(text.strip())
    except Exception as e:
        print(f"  [skip] {source}->{target}: {text[:30]}... — {e}")
        return None


def escape_sql(s: str) -> str:
    return s.replace("'", "''")


def main():
    root = Path(__file__).parent.parent.parent  # Restodocks/
    EN_RU, EN_ES = _load_dicts(root)
    world_path = root / "world_products.json"
    if not world_path.exists():
        print(f"Файл не найден: {world_path}")
        print("Скрипт должен запускаться из restodocks_flutter/")
        return

    with open(world_path, encoding="utf-8") as f:
        world = json.load(f)

    # Собираем уникальные (text, source_lang) для перевода в TR
    to_translate: dict[tuple[str, str], str] = {}  # (text, lang) -> will get TR
    for p in world:
        en_name = (p.get("name") or "").strip()
        if not en_name:
            continue
        ru_name = EN_RU.get(en_name, en_name)
        es_name = EN_ES.get(en_name, en_name)
        to_translate[(en_name, "en")] = ""
        if ru_name != en_name:
            to_translate[(ru_name, "ru")] = ""
        if es_name != en_name and es_name != ru_name:
            to_translate[(es_name, "es")] = ""

    print(f"Уникальных пар (название, язык) для перевода в TR: {len(to_translate)}")
    print("Перевожу через MyMemory (бесплатно)...")

    translated = 0
    for (text, src_lang) in list(to_translate.keys()):
        result = translate_one(text, src_lang, "tr")
        if result and result.strip():
            to_translate[(text, src_lang)] = result.strip()
            translated += 1
        else:
            del to_translate[(text, src_lang)]
        if translated % 50 == 0 and translated > 0:
            print(f"  {translated}...")
        time.sleep(0.15)  # Ограничение запросов MyMemory

    print(f"Переведено: {translated}")

    # Генерируем SQL (в корне restodocks_flutter)
    out_path = Path(__file__).resolve().parent.parent / "seed_translation_cache.sql"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("-- Предзаполнение translation_cache: продукты RU/EN/ES -> TR\n")
        f.write("-- Запустить в Supabase SQL Editor\n")
        f.write("INSERT INTO translation_cache (source_text, source_lang, target_lang, translated)\n")
        f.write("VALUES\n")
        rows = []
        for (text, src_lang), tr_text in to_translate.items():
            if tr_text:
                rows.append(
                    f"  ('{escape_sql(text)}', '{src_lang.upper()}', 'TR', '{escape_sql(tr_text)}')"
                )
        f.write(",\n".join(rows))
        f.write("\nON CONFLICT (source_text, source_lang, target_lang) DO UPDATE SET translated = EXCLUDED.translated;\n")

    print(f"SQL сохранён: {out_path}")
    print("Выполните его в Supabase Dashboard → SQL Editor")


if __name__ == "__main__":
    main()
