#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
migrate_texts_to_i18n.py
Запускается из корня проекта Swift. Найдёт простые вхождения Text("...")
и заменит их на Text(lang.t("key")). Обновит localization.json.
Сделайте бэкап проекта перед запуском!
"""

import re
import os
import json
import argparse
from pathlib import Path
from collections import OrderedDict
import unicodedata

# --- Настройки ---
SWIFT_ROOT = "."               # папка проекта
LOCALIZATION_FILE = "localization.json"  # файл словаря (создастся если нет)
# Поддерживаемые языки (в этом порядке будем добавлять)
LANGS = ["ru","en","es","de","fr"]

# Регекс для простых Text("...") — не ловит интерполяцию и многострочные.
TEXT_RE = re.compile(r'Text\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*\)')

# функция создания ключей
def slugify(text):
    # Обрезаем длинные строки, приводим к lower, убираем диакритику
    txt = text.strip().lower()
    txt = unicodedata.normalize("NFD", txt)
    txt = "".join(ch for ch in txt if unicodedata.category(ch) != "Mn")
    # оставляем буквы/цифры и пробел/-
    txt = re.sub(r'[^0-9a-zа-яё \-]', '', txt)
    txt = re.sub(r'\s+', '_', txt)
    txt = txt[:60]
    if not txt:
        txt = "key"
    return txt

def load_localization(path):
    if not path.exists():
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_localization(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)

def contains_cyrillic(s):
    return bool(re.search('[\u0400-\u04FF]', s))

def main(root, localization_file):
    root = Path(root)
    loc_path = Path(localization_file)
    translations = load_localization(loc_path)
    if translations is None:
        translations = {}

    # map original -> key
    mapping = {}
    used_keys = set(translations.keys())

    changed_files = []

    # сначала пробежимся и соберём все строки
    for swift_path in root.rglob("*.swift"):
        text = swift_path.read_text(encoding="utf-8")
        matches = list(TEXT_RE.finditer(text))
        if not matches:
            continue

        original_strings = [m.group(1) for m in matches]
        # если ничего нового — пропускаем
        file_changed = False
        new_text = text

        for orig in original_strings:
            if orig in mapping:
                key = mapping[orig]
            else:
                # попытка сделать читабельный ключ
                candidate = slugify(orig)
                # добавим префикс по имени файла, чтобы уменьшить коллизии
                prefix = swift_path.stem.lower()
                base_key = f"{prefix}_{candidate}"
                key = base_key
                idx = 1
                while key in used_keys:
                    key = f"{base_key}_{idx}"
                    idx += 1
                used_keys.add(key)
                mapping[orig] = key

                # добавляем в translations (по LANGS)
                # если строка содержит кириллицу — ставим ru = orig, en empty string
                entry = {}
                if contains_cyrillic(orig):
                    entry["ru"] = orig
                    entry["en"] = ""
                else:
                    entry["en"] = orig
                    entry["ru"] = ""
                # и для остальных добавляем пустые
                for L in LANGS:
                    if L not in entry:
                        entry[L] = entry.get("en","") if entry.get("en","") else ""
                translations[key] = entry

            # заменяем все вхождения EXACT
            # экранируем оригинал для regex
            escaped = re.escape(orig)
            # заменить Text("orig") на Text(lang.t("key"))
            new_text, nsub = re.subn(r'Text\(\s*"' + escaped + r'"\s*\)', f'Text(lang.t("{key}"))', new_text)
            if nsub > 0:
                file_changed = True

        if file_changed:
            # backup
            bak = swift_path.with_suffix(swift_path.suffix + ".bak")
            swift_path.rename(bak)
            # записать новый файл
            swift_path.write_text(new_text, encoding="utf-8")
            changed_files.append(str(swift_path))

    # сохранить локализацию
    save_localization(loc_path, translations)

    # вывод отчёта
    print("=== Migration finished ===")
    print(f"Localization file: {loc_path}")
    print(f"Updated {len(changed_files)} swift files:")
    for f in changed_files:
        print("  -", f)
    print("")
    print("Added/updated keys:")
    for orig, key in mapping.items():
        print(f'  "{key}": "{orig}"')
    print("\n*** Backups saved by renaming original.swift -> original.swift.bak ***")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=SWIFT_ROOT, help="project root folder")
    parser.add_argument("--local", default=LOCALIZATION_FILE, help="localization json filename")
    args = parser.parse_args()
    main(args.root, args.local)
