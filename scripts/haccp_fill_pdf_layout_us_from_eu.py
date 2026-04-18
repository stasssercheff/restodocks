#!/usr/bin/env python3
"""
Fill missing haccp_*_layout_us keys from the corresponding *_layout_eu per locale.

US PDF family uses suffix _layout_us; many table keys only had EU/GB/TR variants,
so US exports fell back to long generic column titles. EU short titles are copied as
the US print baseline (same column density); tune English (en) separately if needed.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALIZABLE = ROOT / "restodocks_flutter" / "assets" / "translations" / "localizable.json"


def main() -> int:
    raw = LOCALIZABLE.read_text(encoding="utf-8")
    data = json.loads(raw)
    added = 0
    for lang, bundle in data.items():
        if not isinstance(bundle, dict):
            continue
        for key, val in list(bundle.items()):
            if not key.endswith("_layout_eu"):
                continue
            base = key[: -len("_layout_eu")]
            us_key = f"{base}_layout_us"
            if us_key not in bundle:
                bundle[us_key] = val
                added += 1
        cap_eu = "haccp_pdf_health_form_caption_layout_eu"
        cap_us = "haccp_pdf_health_form_caption_layout_us"
        if cap_eu in bundle and cap_us not in bundle:
            bundle[cap_us] = bundle[cap_eu]
            added += 1

    LOCALIZABLE.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"OK: added {added} missing *_layout_us / caption keys.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
