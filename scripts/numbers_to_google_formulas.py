#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Конвертирует формулы Apple Numbers в синтаксис Google Таблиц в .xlsx файле.

Использование:
  1. В Apple Numbers: Файл → Экспорт в → Excel (.xlsx)
     ИЛИ если уже в Google: Файл → Скачать → Microsoft Excel (.xlsx)
  2. Запуск: python numbers_to_google_formulas.py путь/к/файлу.xlsx
  3. Создаётся файл путь/к/файлу_google.xlsx — загрузи его в Google Таблицы.

Замены:
  - Numbers:  Sheet 2::Table 1::B2   →  Google:  'Sheet 2'!B2
  - Numbers:  Table 2::A1            →  Google:  Table 2!A1
"""
import re
import sys
from pathlib import Path

try:
    import openpyxl
except ImportError:
    print("Установи openpyxl: pip install openpyxl")
    sys.exit(1)


def needs_quotes(name: str) -> bool:
    """Имена с пробелами/цифрами в начале нужно в кавычках в Google."""
    return bool(re.search(r"\s|^\d", name.strip()))


def convert_formula(text: str) -> str:
    """
    Numbers:  'Sheet 2'::'Table 1'::B2  или  Sheet 2::Table 1::B2
    Google:   'Sheet 2'!B2
    """
    if not text or not str(text).strip().startswith("="):
        return text
    s = str(text)

    # Кавычки в Numbers: 'Sheet 2'::'Table 1'::  → оставляем имя листа в кавычках, убираем Table
    # Паттерн: (опционально 'имя' или имя)::(опционально 'имя' или имя)::  → 'имя'! или имя!
    def replace_sheet_table(match):
        part1 = match.group(1).strip().lstrip("=+-,(")
        # part2 = match.group(2)  # Table — не используем
        if needs_quotes(part1) or ("'" in part1 and part1[0] != "'"):
            name = part1 if part1.startswith("'") and part1.endswith("'") else f"'{part1}'"
        else:
            name = part1
        return f"{name}!"

    # Два уровня: Sheet::Table::  (имя листа/таблицы без операторов +-*/,)
    s = re.sub(
        r"('(?:[^']*)'|[^:+\-*/(),]+)::([^:+\-*/(),]+)::",
        replace_sheet_table,
        s,
    )

    # Один уровень: Table::  →  Table!
    def replace_table(match):
        part = match.group(1).strip().lstrip("=+-,(")
        if needs_quotes(part) or ("'" in part and part[0] != "'"):
            name = part if part.startswith("'") and part.endswith("'") else f"'{part}'"
        else:
            name = part
        return f"{name}!"

    s = re.sub(
        r"('(?:[^']*)'|[^:!+\-*/(),]+)::",
        replace_table,
        s,
    )

    return s


def convert_workbook(path_in: str, path_out: str | None = None) -> None:
    path_in = Path(path_in)
    if not path_in.exists():
        print(f"Файл не найден: {path_in}")
        sys.exit(1)
    if path_in.suffix.lower() != ".xlsx":
        print("Нужен файл .xlsx")
        sys.exit(1)

    path_out = path_out or path_in.parent / f"{path_in.stem}_google.xlsx"
    path_out = Path(path_out)

    # Загружаем БЕЗ data_only, чтобы видеть формулы
    wb = openpyxl.load_workbook(path_in, data_only=False)
    total = 0
    for ws in wb.worksheets:
        for row in ws.iter_rows():
            for cell in row:
                if cell.data_type == "f" and cell.value:
                    old_val = str(cell.value)
                    new_val = convert_formula(old_val)
                    if new_val != old_val:
                        cell.value = new_val
                        total += 1

    wb.save(path_out)
    print(f"Готово. Изменено формул: {total}. Сохранено: {path_out}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("Пример: python numbers_to_google_formulas.py ~/Downloads/Себестоимость.xlsx")
        sys.exit(0)
    convert_workbook(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)


if __name__ == "__main__":
    main()
