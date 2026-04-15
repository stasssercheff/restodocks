#!/usr/bin/env python3
"""
Одноразовое добавление пакета ключей + перевод ru→остальные (deep-translator).

Запуск из restodocks_flutter:
  pip install deep-translator
  python3 scripts/i18n_seed_batch_ui.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("pip install deep-translator", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets" / "translations" / "localizable.json"

# en + ru заданы вручную; kk,de,es,fr,it,tr,vi — из ru через MT
BATCH: dict[str, dict[str, str]] = {
    "menu_export_scope_all": {"en": "All", "ru": "Все"},
    "menu_export_scope_selected": {"en": "Selected", "ru": "Выборочно"},
    "menu_export_profitable_above_target": {
        "en": "Profitable (above target)",
        "ru": "Выгодно (выше цели)",
    },
    "menu_export_unprofitable_below_target": {
        "en": "Unprofitable (below target)",
        "ru": "Невыгодно (ниже цели)",
    },
    "menu_export_doc_title_foodcost": {
        "en": "Food cost menu",
        "ru": "Фудкост меню",
    },
    "menu_pdf_label_date": {"en": "Date:", "ru": "Дата:"},
    "menu_pdf_label_establishment": {"en": "Establishment:", "ru": "Заведение:"},
    "menu_pdf_label_chef": {"en": "Chef:", "ru": "Шеф:"},
    "menu_excel_cell_date": {"en": "Date", "ru": "Дата"},
    "menu_excel_cell_establishment": {"en": "Establishment", "ru": "Заведение"},
    "menu_excel_cell_chef": {"en": "Chef", "ru": "Шеф"},
    "file_format_short_excel": {"en": "Excel", "ru": "Excel"},
    "export_format_csv": {"en": "CSV", "ru": "CSV"},
    "haccp_field_helper_plus_or_arrow": {
        "en": "Plus — add to list, arrow — pick saved",
        "ru": "Плюс — в список, стрелка — выбрать",
    },
    "haccp_tooltip_save_to_journal_list": {
        "en": "Save to list (this journal)",
        "ru": "Сохранить в список (этот журнал)",
    },
    "haccp_tooltip_pick_from_saved": {
        "en": "Pick from saved",
        "ru": "Выбрать из сохранённых",
    },
    "product_upload_iiko_warning_title": {
        "en": "Important before upload",
        "ru": "Важно перед загрузкой",
    },
    "product_upload_iiko_warning_body": {
        "en": "Semi-finished products will be added as standalone products and will not appear as \"SF\" in Restodocks.\n\n"
        "We recommend uploading only clean product names.",
        "ru": "ПФ будут добавлены как самостоятельные продукты и не будут отображаться как «ПФ» в системе Restodocks.\n\n"
        "Рекомендуем загружать только чистые продукты.",
    },
    "product_upload_iiko_select_sheet_title": {
        "en": "Select iiko sheet",
        "ru": "Выберите лист iiko",
    },
    "appbar_title_ttk_short": {"en": "Tech card", "ru": "ТТК"},
    "excel_ttk_err_product_store_null": {
        "en": "ProductStore is null",
        "ru": "ProductStore is null",
    },
    "excel_ttk_err_on_update_null": {
        "en": "onUpdate callback is null",
        "ru": "onUpdate callback is null",
    },
    "excel_ttk_err_build": {
        "en": "Error in ExcelStyleTtkTable build",
        "ru": "Error in ExcelStyleTtkTable build",
    },
    "excel_ttk_err_generic": {"en": "Error: {error}", "ru": "Ошибка: {error}"},
    "excel_ttk_err_ingredients_null": {
        "en": "Ingredients is null",
        "ru": "Ingredients is null",
    },
    "excel_ttk_err_ingredient_at_index": {
        "en": "Ingredient at index {index} is null",
        "ru": "Ingredient at index {index} is null",
    },
    "excel_ttk_err_table": {"en": "Error in TTK table", "ru": "Error in TTK table"},
    "excel_ttk_err_product_cell": {
        "en": "Error in product cell",
        "ru": "Error in product cell",
    },
    "excel_ttk_err_dropdown": {"en": "Error in dropdown", "ru": "Error in dropdown"},
    "dev_test_file_url": {"en": "File URL: {url}", "ru": "URL файла: {url}"},
}

TARGET_LANGS = ("kk", "de", "es", "fr", "it", "tr", "vi")


def main() -> None:
    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    translators = {code: GoogleTranslator(source="ru", target=code) for code in TARGET_LANGS}

    for key, langs in BATCH.items():
        en_v = langs["en"]
        ru_v = langs["ru"]
        data["en"][key] = en_v
        data["ru"][key] = ru_v
        for code in TARGET_LANGS:
            try:
                data[code][key] = translators[code].translate(ru_v)
            except Exception as e:
                print(key, code, e, file=sys.stderr)
                data[code][key] = en_v

    JSON_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Wrote", len(BATCH), "keys × locales")


if __name__ == "__main__":
    main()
