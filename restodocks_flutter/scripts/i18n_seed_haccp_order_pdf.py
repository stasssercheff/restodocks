#!/usr/bin/env python3
"""Добавить ключи haccp_order_pdf_* во все локали (ru+en вручную, остальные MT с ru)."""
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

# ru — исходный шаблон; en — параллель для PDF на английском
HACCP_ORDER_PDF: dict[str, dict[str, str]] = {
    "haccp_order_pdf_order_number_title": {
        "ru": "ПРИКАЗ №____",
        "en": "ORDER No. ____",
    },
    "haccp_order_pdf_order_subject": {
        "ru": "«О внедрении системы электронного учета и ведения производственной документации»",
        "en": "“On the introduction of electronic record-keeping and production documentation”",
    },
    "haccp_order_pdf_date_place_template": {
        "ru": "г. ____________ «__» __________ 202 г.",
        "en": "_____________, “__” __________ 202__",
    },
    "haccp_order_pdf_p1_intro_sanpin": {
        "ru": "В целях оптимизации рабочих процессов, обеспечения оперативного контроля и сохранности данных, а также руководствуясь п. 2.22 и п. 3.8 СанПиН 2.3/2.4.3590-20,",
        "en": "To optimize workflows, ensure timely control and data integrity, and in accordance with clauses 2.22 and 3.8 of SanPiN 2.3/2.4.3590-20,",
    },
    "haccp_order_pdf_i_hereby_order": {
        "ru": "ПРИКАЗЫВАЮ:",
        "en": "I HEREBY ORDER:",
    },
    "haccp_order_pdf_p1_body_paragraphs": {
        "ru": "Внедрить в деятельность {organization} систему ведения производственной документации в электронном виде с использованием программного обеспечения (ПО) RestoDocks.\n\n"
        "Утвердить Перечень производственной документации, допущенной к ведению в электронном виде (Приложение №1 к настоящему Приказу).\n\n"
        "Установить, что ведение указанных в Приложении №1 журналов осуществляется преимущественно в электронном формате. Допускается временное ведение документации на бумажных носителях в случае технической необходимости или по решению ответственного лица.\n\n"
        "Установить, что идентификация сотрудника в ПО RestoDocks (уникальный логин и пароль) признается Сторонами использованием простой электронной подписи (ПЭП). Любая запись, внесенная под учетной записью сотрудника, приравнивается к его личной подписи на бумажном носителе.\n\n"
        "Назначить ответственным за контроль ведения, достоверность данных и своевременную выгрузку (печать) электронных журналов: {placeholder_responsible}.\n\n"
        "Контроль за исполнением настоящего приказа оставляю за собой.",
        "en": "Introduce into the operations of {organization} a system of electronic production documentation using the RestoDocks software.\n\n"
        "Approve the List of production documentation permitted to be kept electronically (Appendix No. 1 to this Order).\n\n"
        "Establish that the journals listed in Appendix No. 1 shall be kept primarily in electronic form. Temporary paper-based records are allowed in case of technical necessity or by decision of the responsible person.\n\n"
        "Establish that employee identification in RestoDocks (unique login and password) is deemed use of a simple electronic signature (SES). Any entry made under an employee account is equivalent to their handwritten signature on paper.\n\n"
        "Appoint as responsible for supervision, data accuracy and timely export (printing) of electronic journals: {placeholder_responsible}.\n\n"
        "I retain control over the execution of this order.",
    },
    "haccp_order_pdf_placeholder_position_fio": {
        "ru": "[Должность/ФИО]",
        "en": "[Position / full name]",
    },
    "haccp_order_pdf_sign_manager_line": {
        "ru": "Руководитель заведения: ___________ /{director_fio}/",
        "en": "Head of establishment: ___________ /{director_fio}/",
    },
    "haccp_order_pdf_caption_signature_fio": {
        "ru": "(Подпись) (ФИО)",
        "en": "(Signature) (full name)",
    },
    "haccp_order_pdf_seal_initials": {
        "ru": "М.П.",
        "en": "Seal",
    },
    "haccp_order_pdf_appendix1_heading": {
        "ru": "Приложение №1 к Приказу №____ от «__» ________ 202 г.",
        "en": "Appendix No. 1 to Order No. ____ dated “__” __________ 202__",
    },
    "haccp_order_pdf_appendix1_manifest_title": {
        "ru": "ПЕРЕЧЕНЬ ПРОИЗВОДСТВЕННОЙ ДОКУМЕНТАЦИИ К ВЕДЕНИЮ В ЭЛЕКТРОННОМ ВИДЕ",
        "en": "LIST OF PRODUCTION DOCUMENTATION TO BE KEPT IN ELECTRONIC FORM",
    },
    "haccp_order_pdf_col_index": {
        "ru": "№",
        "en": "No.",
    },
    "haccp_order_pdf_col_journal_name": {
        "ru": "Наименование журнала",
        "en": "Journal name",
    },
    "haccp_order_pdf_col_record_format": {
        "ru": "Форма ведения",
        "en": "Record format",
    },
    "haccp_order_pdf_col_responsible_role": {
        "ru": "Ответственное лицо (должность)",
        "en": "Responsible person (position)",
    },
    "haccp_order_pdf_row_format_mixed": {
        "ru": "Электронно / Бумажно",
        "en": "Electronic / Paper",
    },
    "haccp_order_pdf_appendix_is_integral": {
        "ru": "Данное приложение является неотъемлемой частью Приказа №____.",
        "en": "This appendix is an integral part of Order No. ____.",
    },
    "haccp_order_pdf_i_approve_caps": {
        "ru": "УТВЕРЖДАЮ:",
        "en": "I APPROVE:",
    },
    "haccp_order_pdf_sign_manager_date_line": {
        "ru": "Руководитель заведения: ___________ /{director_fio}/ «» ________ 202 г.",
        "en": "Head of establishment: ___________ /{director_fio}/ “” __________ 202__",
    },
    "haccp_order_pdf_caption_signature_fio_date": {
        "ru": "(Подпись) (ФИО) (Дата)",
        "en": "(Signature) (full name) (date)",
    },
    "haccp_order_pdf_ack_title": {
        "ru": "ЛИСТ ОЗНАКОМЛЕНИЯ СОТРУДНИКОВ С ПРИКАЗОМ №____ И ПРАВИЛАМИ ИСПОЛЬЗОВАНИЯ ПЭП",
        "en": "EMPLOYEE ACKNOWLEDGMENT SHEET FOR ORDER NO. ____ AND SES USE RULES",
    },
    "haccp_order_pdf_ack_statement": {
        "ru": "Настоящим подтверждаю, что ознакомлен с Приказом №____ от «__» ________ 202 г. и правилами работы в ПО RestoDocks. "
        "Подтверждаю свое согласие на то, что использование моих персональных учетных данных (логина и пароля) признается использованием моей простой электронной подписи (ПЭП). "
        "Все записи, внесенные мной в электронные журналы, имеют юридическую силу, аналогичную моей рукописной подписи. "
        "Обязуюсь не передавать свои учетные данные третьим лицам.",
        "en": "I hereby confirm that I have read Order No. ____ dated “__” __________ 202__ and the rules for using RestoDocks. "
        "I agree that use of my account credentials (login and password) constitutes use of my simple electronic signature (SES). "
        "All entries I make in electronic journals have legal effect equivalent to my handwritten signature. "
        "I undertake not to share my credentials with third parties.",
    },
    "haccp_order_pdf_p3_col_index": {
        "ru": "№",
        "en": "No.",
    },
    "haccp_order_pdf_p3_col_employee_fio": {
        "ru": "ФИО сотрудника",
        "en": "Employee full name",
    },
    "haccp_order_pdf_p3_col_position": {
        "ru": "Должность",
        "en": "Position",
    },
    "haccp_order_pdf_p3_col_ack_date": {
        "ru": "Дата ознакомления",
        "en": "Acknowledgment date",
    },
    "haccp_order_pdf_p3_col_own_signature": {
        "ru": "Личная подпись",
        "en": "Signature",
    },
    "haccp_order_pdf_ack_sheet_note": {
        "ru": "Лист ознакомления является приложением к Приказу №____.",
        "en": "This acknowledgment sheet is an appendix to Order No. ____.",
    },
    "haccp_order_pdf_ack_keeper_line": {
        "ru": "Ответственный за ведение листа: ___________ /___________________/",
        "en": "Person responsible for this sheet: ___________ /___________________/",
    },
    "haccp_order_pdf_caption_signature_fio_short": {
        "ru": "(Подпись) (ФИО)",
        "en": "(Signature) (full name)",
    },
    "haccp_order_pdf_default_director_title": {
        "ru": "Генеральный директор",
        "en": "Chief Executive Officer",
    },
}

# 12 строк приложения: только наименование журнала и колонка «ответственный»
JOURNAL_ROWS: list[tuple[str, str, str]] = [
    ("haccp_order_pdf_jr01", "Гигиенический журнал (сотрудники)", "Шеф-повар / Су-шеф"),
    ("haccp_order_pdf_jr02", "Журнал учета темп. режима холодильников", "Ответственный по цеху"),
    ("haccp_order_pdf_jr03", "Журнал учета темп. и влажности складов", "Кладовщик / Шеф-повар"),
    ("haccp_order_pdf_jr04", "Журнал бракеража готовой продукции", "Бракеражная комиссия"),
    ("haccp_order_pdf_jr05", "Журнал бракеража скоропортящейся продукции", "Кладовщик / Су-шеф"),
    ("haccp_order_pdf_jr06", "Учёт фритюрных жиров", "Повар горячего цеха"),
    ("haccp_order_pdf_jr07", "Журнал учёта личных медицинских книжек", "Управляющий / Шеф"),
    ("haccp_order_pdf_jr08", "Журнал учёта медосмотров", "Управляющий / Шеф"),
    ("haccp_order_pdf_jr09", "Журнал учёта дезсредств и работ", "Шеф-повар"),
    ("haccp_order_pdf_jr10", "Журнал мойки и дезинфекции оборудования", "Ответственный по цеху"),
    ("haccp_order_pdf_jr11", "Журнал-график генеральных уборок", "Су-шеф"),
    ("haccp_order_pdf_jr12", "Журнал проверки сит/фильтров и магнитов", "Повар заготовочного цеха"),
]

EN_JOURNAL = [
    ("Hygiene log (employees)", "Head chef / Sous chef"),
    ("Refrigeration temperature log", "Kitchen section supervisor"),
    ("Warehouse temperature and humidity log", "Storekeeper / Head chef"),
    ("Finished product spoilage log", "Spoilage commission"),
    ("Perishable product spoilage log", "Storekeeper / Sous chef"),
    ("Frying oil tracking", "Hot kitchen cook"),
    ("Personal medical book log", "Manager / Head chef"),
    ("Medical examination log", "Manager / Head chef"),
    ("Disinfectant and work log", "Head chef"),
    ("Equipment washing and disinfection log", "Kitchen section supervisor"),
    ("General cleaning schedule log", "Sous chef"),
    ("Sieve/filter and magnet inspection log", "Prep kitchen cook"),
]


def main() -> None:
    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    for k, v in HACCP_ORDER_PDF.items():
        data["ru"][k] = v["ru"]
        data["en"][k] = v["en"]
    for i, ((key_base, ru_name, ru_resp), (en_name, en_resp)) in enumerate(
        zip(JOURNAL_ROWS, EN_JOURNAL)
    ):
        data["ru"][f"{key_base}_name"] = ru_name
        data["ru"][f"{key_base}_resp"] = ru_resp
        data["en"][f"{key_base}_name"] = en_name
        data["en"][f"{key_base}_resp"] = en_resp

    ru_src = data["ru"]
    targets = ("kk", "de", "es", "fr", "it", "tr", "vi")
    translators = {lang: GoogleTranslator(source="ru", target=lang) for lang in targets}
    all_keys = list(HACCP_ORDER_PDF.keys())
    for jb, _, _ in JOURNAL_ROWS:
        all_keys.append(f"{jb}_name")
        all_keys.append(f"{jb}_resp")

    for key in all_keys:
        text_ru = ru_src[key]
        for lang in targets:
            try:
                data[lang][key] = translators[lang].translate(text_ru)
            except Exception as e:
                print(key, lang, e, file=sys.stderr)
                data[lang][key] = data["en"][key]

    # MT часто путает «цех» с «семинаром» в kk — подмена после перевода
    _kk_haccp_fixes: dict[str, str] = {
        "haccp_order_pdf_jr02_resp": "Цех бойынша жауапты",
        "haccp_order_pdf_jr10_resp": "Цех бойынша жауапты",
    }
    for kk_key, kk_val in _kk_haccp_fixes.items():
        data["kk"][kk_key] = kk_val

    JSON_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Added", len(all_keys), "haccp_order_pdf keys to all locales")


if __name__ == "__main__":
    main()
