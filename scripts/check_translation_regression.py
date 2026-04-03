#!/usr/bin/env python3
import json
import sys
from pathlib import Path


FILE = Path("restodocks_flutter/assets/translations/localizable.json")
REQUIRED_KEYS = [
    "confirm_email_hint",
    "confirm_email_step3",
    "co_owner_invitation_title",
    "co_owner_invitation_description",
    "accept_invitation",
    "invitation_not_found_or_expired",
]
REQUIRED_LOCALES = ["ru", "en", "es", "it", "tr", "vi"]


def main() -> int:
    if not FILE.exists():
        print(f"Missing file: {FILE}", file=sys.stderr)
        return 1

    data = json.loads(FILE.read_text(encoding="utf-8"))
    failed = False

    for loc in REQUIRED_LOCALES:
        obj = data.get(loc)
        if not isinstance(obj, dict):
            print(f"[FAIL] locale '{loc}' missing")
            failed = True
            continue
        for key in REQUIRED_KEYS:
            val = obj.get(key)
            if not isinstance(val, str) or not val.strip():
                print(f"[FAIL] {loc}.{key} missing/empty")
                failed = True

    if failed:
        return 1

    print("OK: translation regression check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
