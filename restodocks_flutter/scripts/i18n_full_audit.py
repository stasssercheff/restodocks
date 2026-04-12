#!/usr/bin/env python3
"""
Полный автоматический аудит i18n **без** ручного кликанья по сайту.

1) Паритет ключей: у каждого языка тот же набор ключей, что у en.
2) «Зазоры» перевода: значение языка совпадает с en, при этом ru отличается от en
   (типичный непереведённый плейсхолдер). Список **всех** таких ключей в отчёт.
3) Эвристика по Dart: подозрительные строки в UI без loc.t() (как i18n_scan_hardcoded.py).

Запуск:
  cd restodocks_flutter && python3 scripts/i18n_full_audit.py

Из корня репозитория Restodocks (обёртка):
  python3 scripts/i18n_full_audit.py

Опции:
  python3 scripts/i18n_full_audit.py --out scripts/i18n_audit_report.txt
  python3 scripts/i18n_full_audit.py --langs kk,de --no-dart   # только словарь

Результат: печать в stdout + опционально файл (по умолчанию scripts/i18n_audit_report.txt).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "assets" / "translations" / "localizable.json"
LANGS = ("ru", "en", "es", "kk", "de", "fr", "it", "tr", "vi")
DEFAULT_OUT = ROOT / "scripts" / "i18n_audit_report.txt"


def _gap_keys_vs_en(
    data: dict[str, dict[str, str]], lang: str
) -> list[str]:
    """Ключи, где loc == en (trim), ru есть и ru != en."""
    en = data.get("en", {})
    ru = data.get("ru", {})
    loc = data.get(lang, {})
    out: list[str] = []
    for k in en:
        ev = (en.get(k) or "").strip()
        rv = (ru.get(k) or "").strip()
        lv = (loc.get(k) or "").strip()
        if not rv or rv == ev:
            continue
        if lv == ev:
            out.append(k)
    return sorted(out)


def _parity_issues(data: dict) -> list[str]:
    en_keys = set(data.get("en", {}).keys())
    lines: list[str] = []
    for code in LANGS:
        if code == "en":
            continue
        block = data.get(code)
        if not isinstance(block, dict):
            lines.append(f"{code}: блок отсутствует")
            continue
        sk = set(block.keys())
        miss = en_keys - sk
        extra = sk - en_keys
        if miss or extra:
            lines.append(
                f"{code}: missing_vs_en={len(miss)} extra_vs_en={len(extra)}"
            )
    return lines


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--langs",
        default=",".join(x for x in LANGS if x not in ("ru", "en")),
        help="Коды через запятую (без en). По умолчанию все не-en из словаря.",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Файл отчёта (по умолчанию {DEFAULT_OUT})",
    )
    ap.add_argument("--no-dart", action="store_true", help="Не сканировать lib/*.dart")
    ap.add_argument("--stdout-only", action="store_true", help="Не писать файл")
    args = ap.parse_args()

    raw = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    lines: list[str] = []
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines.append(f"i18n full audit  {ts}")
    lines.append(f"localizable.json: {JSON_PATH}")
    lines.append("")

    # --- parity ---
    pi = _parity_issues(raw)
    if pi:
        lines.append("=== PARITY ISSUES ===")
        lines.extend(pi)
    else:
        lines.append("=== PARITY === OK (все блоки совпадают по множеству ключей с en)")
    lines.append("")

    # --- gaps per lang ---
    want = [x.strip() for x in args.langs.split(",") if x.strip()]
    lines.append("=== DICTIONARY GAPS (value == en, ru != en) ===")
    lines.append(
        "Смысл: строка в JSON для языка всё ещё как в английском, "
        "хотя русский уже другой — интерфейс может выглядеть «по-английски»."
    )
    lines.append("")
    total_gaps = 0
    for lang in want:
        if lang not in raw or lang == "en":
            continue
        g = _gap_keys_vs_en(raw, lang)
        total_gaps += len(g)
        lines.append(f"--- {lang}: {len(g)} keys ---")
        for k in g:
            lines.append(f"  {k}")
        lines.append("")

    lines.append(f"TOTAL gap keys (sum over langs, keys may repeat): {total_gaps}")
    lines.append("")

    # --- dart scan ---
    dart_hits = 0
    if not args.no_dart:
        lines.append("=== DART HEURISTIC (possible hardcoded UI strings) ===")
        lines.append(
            "Источник: i18n_scan_hardcoded.py — нужна ручная проверка ложных срабатываний."
        )
        lines.append("")
        script = ROOT / "scripts" / "i18n_scan_hardcoded.py"
        proc = subprocess.run(
            [sys.executable, str(script), "--json"],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=120,
        )
        if proc.returncode != 0:
            lines.append(f"scan failed: {proc.stderr[:500]}")
        else:
            try:
                hits = json.loads(proc.stdout)
                dart_hits = len(hits)
                lines.append(f"count: {dart_hits}")
                for h in hits:
                    lines.append(
                        f"  {h.get('file')}:{h.get('line')}  [{h.get('fragment')!r}]"
                    )
            except json.JSONDecodeError:
                lines.append("could not parse scan JSON")
                lines.append(proc.stdout[:800])
        lines.append("")

    text = "\n".join(lines) + "\n"
    print(text, end="")
    if not args.stdout_only:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"Wrote {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
