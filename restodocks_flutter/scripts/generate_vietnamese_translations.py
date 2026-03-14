#!/usr/bin/env python3
"""Generate Vietnamese (vi) translations from English (en) using deep_translator.
   DeepL supports Vietnamese; this script uses Google/MyMemory for batch translation.
   For products/TTK the app uses DeepL via translate-text Edge Function."""
import json
import time
from pathlib import Path

try:
    from deep_translator import GoogleTranslator, MyMemoryTranslator
except ImportError:
    print("Run: pip install deep-translator")
    exit(1)


def translate_one(text: str, fallback: str) -> str:
    """Translate one text, try Google then MyMemory, return fallback on error."""
    if not text or not text.strip():
        return fallback
    try:
        r = GoogleTranslator(source="en", target="vi").translate(text)
        if r:
            return r
    except Exception:
        pass
    try:
        r = MyMemoryTranslator(source="en", target="vi").translate(text)
        if r:
            return r
    except Exception:
        pass
    return fallback


def translate_batch(texts: list[str], fallbacks: list[str], use_batch: bool = True) -> list[str]:
    """Translate texts. Try batch first, fallback to one-by-one on error."""
    if not texts:
        return []
    if use_batch:
        try:
            return GoogleTranslator(source="en", target="vi").translate_batch(texts)
        except Exception:
            pass
    return [translate_one(t, f) for t, f in zip(texts, fallbacks)]


def main():
    root = Path(__file__).parent.parent
    path = root / "assets/translations/localizable.json"
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    en = data.get("en", {})
    if not en:
        print("No 'en' section found")
        return

    vi = {}
    keys = list(en.keys())
    print(f"Translating {len(keys)} keys to Vietnamese...")

    batch_size = 15
    for i in range(0, len(keys), batch_size):
        batch_keys = keys[i : i + batch_size]
        batch_values = [str(en[k]) for k in batch_keys]
        translated = translate_batch(batch_values, batch_values, use_batch=True)
        for k, v in zip(batch_keys, translated):
            vi[k] = v if v else str(en[k])
        print(f"  {min(i + batch_size, len(keys))}/{len(keys)} done")
        if i + batch_size < len(keys):
            time.sleep(1.5)

    data["vi"] = vi
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"Done. Vietnamese section has {len(vi)} keys.")


if __name__ == "__main__":
    main()
