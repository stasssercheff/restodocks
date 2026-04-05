#!/usr/bin/env python3
"""Import review, iiko inbox, inventory errors — localizable.json (8 locales)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "assets/translations/localizable.json"
LANGS = ("ru", "en", "es", "de", "fr", "it", "tr", "vi")

B = {
    "error_not_logged_in": {
        "ru": "Не авторизован",
        "en": "Not signed in",
        "es": "No ha iniciado sesión",
        "de": "Nicht angemeldet",
        "fr": "Non connecté",
        "it": "Accesso non effettuato",
        "tr": "Giriş yapılmadı",
        "vi": "Chưa đăng nhập",
    },
    "error_generic": {
        "ru": "Ошибка: {error}",
        "en": "Error: {error}",
        "es": "Error: {error}",
        "de": "Fehler: {error}",
        "fr": "Erreur : {error}",
        "it": "Errore: {error}",
        "tr": "Hata: {error}",
        "vi": "Lỗi: {error}",
    },
    "import_review_save_error": {
        "ru": "Ошибка сохранения: {error}",
        "en": "Save error: {error}",
        "es": "Error al guardar: {error}",
        "de": "Speicherfehler: {error}",
        "fr": "Erreur d’enregistrement : {error}",
        "it": "Errore di salvataggio: {error}",
        "tr": "Kaydetme hatası: {error}",
        "vi": "Lỗi lưu: {error}",
    },
    "import_review_price_old_new": {
        "ru": "Было: {old}{cur} → Станет: {new}{cur}",
        "en": "Was: {old}{cur} → Will be: {new}{cur}",
        "es": "Antes: {old}{cur} → Quedará: {new}{cur}",
        "de": "War: {old}{cur} → Wird: {new}{cur}",
        "fr": "Était : {old}{cur} → Sera : {new}{cur}",
        "it": "Era: {old}{cur} → Diventa: {new}{cur}",
        "tr": "Eski: {old}{cur} → Yeni: {new}{cur}",
        "vi": "Trước: {old}{cur} → Sau: {new}{cur}",
    },
    "import_review_price_new_only": {
        "ru": "Новая цена: {price}{cur}",
        "en": "New price: {price}{cur}",
        "es": "Precio nuevo: {price}{cur}",
        "de": "Neuer Preis: {price}{cur}",
        "fr": "Nouveau prix : {price}{cur}",
        "it": "Nuovo prezzo: {price}{cur}",
        "tr": "Yeni fiyat: {price}{cur}",
        "vi": "Giá mới: {price}{cur}",
    },
    "import_review_price_line": {
        "ru": "Цена: {price}{cur}",
        "en": "Price: {price}{cur}",
        "es": "Precio: {price}{cur}",
        "de": "Preis: {price}{cur}",
        "fr": "Prix : {price}{cur}",
        "it": "Prezzo: {price}{cur}",
        "tr": "Fiyat: {price}{cur}",
        "vi": "Giá: {price}{cur}",
    },
    "moderation_cat_name_fix_abbr": {
        "ru": "Назв.",
        "en": "Name",
        "es": "Nom.",
        "de": "Name",
        "fr": "Nom",
        "it": "Nome",
        "tr": "Ad",
        "vi": "Tên",
    },
    "moderation_cat_price_anomaly_abbr": {
        "ru": "Цена",
        "en": "Price",
        "es": "Precio",
        "de": "Preis",
        "fr": "Prix",
        "it": "Prezzo",
        "tr": "Fiyat",
        "vi": "Giá",
    },
    "moderation_cat_price_update_abbr": {
        "ru": "Обнов.",
        "en": "Upd.",
        "es": "Act.",
        "de": "Akt.",
        "fr": "Màj",
        "it": "Agg.",
        "tr": "Günc.",
        "vi": "CN",
    },
    "moderation_cat_new_product_abbr": {
        "ru": "Нов.",
        "en": "New",
        "es": "Nuevo",
        "de": "Neu",
        "fr": "Nouv.",
        "it": "Nuovo",
        "tr": "Yeni",
        "vi": "Mới",
    },
    "file_saved_snackbar": {
        "ru": "Сохранено: {file}",
        "en": "Saved: {file}",
        "es": "Guardado: {file}",
        "de": "Gespeichert: {file}",
        "fr": "Enregistré : {file}",
        "it": "Salvato: {file}",
        "tr": "Kaydedildi: {file}",
        "vi": "Đã lưu: {file}",
    },
    "iiko_excel_col_code": {
        "ru": "Код",
        "en": "Code",
        "es": "Código",
        "de": "Code",
        "fr": "Code",
        "it": "Codice",
        "tr": "Kod",
        "vi": "Mã",
    },
    "iiko_excel_col_name": {
        "ru": "Наименование",
        "en": "Name",
        "es": "Nombre",
        "de": "Bezeichnung",
        "fr": "Désignation",
        "it": "Denominazione",
        "tr": "Ad",
        "vi": "Tên",
    },
    "iiko_excel_col_unit": {
        "ru": "Ед.изм.",
        "en": "Unit",
        "es": "Ud.",
        "de": "Einheit",
        "fr": "Unité",
        "it": "UdM",
        "tr": "Birim",
        "vi": "ĐVT",
    },
    "iiko_excel_col_actual_stock": {
        "ru": "Остаток фактический",
        "en": "Actual stock",
        "es": "Stock real",
        "de": "Istbestand",
        "fr": "Stock réel",
        "it": "Giacenza effettiva",
        "tr": "Fiili stok",
        "vi": "Tồn thực tế",
    },
    "download_xlsx_tooltip": {
        "ru": "Скачать xlsx",
        "en": "Download xlsx",
        "es": "Descargar xlsx",
        "de": "xlsx herunterladen",
        "fr": "Télécharger xlsx",
        "it": "Scarica xlsx",
        "tr": "xlsx indir",
        "vi": "Tải xlsx",
    },
    "iiko_inbox_subtitle": {
        "ru": "Дата: {date}  •  Сотрудник: {employee}",
        "en": "Date: {date}  •  Employee: {employee}",
        "es": "Fecha: {date}  •  Empleado: {employee}",
        "de": "Datum: {date}  •  Mitarbeiter: {employee}",
        "fr": "Date : {date}  •  Employé : {employee}",
        "it": "Data: {date}  •  Dipendente: {employee}",
        "tr": "Tarih: {date}  •  Çalışan: {employee}",
        "vi": "Ngày: {date}  •  Nhân viên: {employee}",
    },
    "iiko_inbox_filled_stats": {
        "ru": "Заполнено: {filled} из {total} позиций",
        "en": "Filled: {filled} of {total} items",
        "es": "Rellenado: {filled} de {total} posiciones",
        "de": "Ausgefüllt: {filled} von {total} Positionen",
        "fr": "Rempli : {filled} sur {total} lignes",
        "it": "Compilati: {filled} di {total} righe",
        "tr": "Doldurulan: {filled} / {total} kalem",
        "vi": "Đã điền: {filled}/{total} mục",
    },
    "iiko_inbox_col_group": {
        "ru": "Группа",
        "en": "Group",
        "es": "Grupo",
        "de": "Gruppe",
        "fr": "Groupe",
        "it": "Gruppo",
        "tr": "Grup",
        "vi": "Nhóm",
    },
}


def main() -> None:
    data = json.loads(PATH.read_text(encoding="utf-8"))
    for key, per_lang in B.items():
        for lang in LANGS:
            data[lang][key] = per_lang[lang]
    PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("merged", len(B), "keys")


if __name__ == "__main__":
    main()
