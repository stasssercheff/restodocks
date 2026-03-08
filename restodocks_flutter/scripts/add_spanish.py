#!/usr/bin/env python3
"""Add Spanish (es) section to localizable.json by translating from English."""
import json
import re
import time
from pathlib import Path

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("Run: pip install deep-translator")
    exit(1)

BATCH_SIZE = 100

def preserve_placeholders(text):
    placeholders = []
    def repl(m):
        placeholders.append(m.group(0))
        return f"__PH{len(placeholders)-1}__"
    clean = re.sub(r'\{[^}]+\}|%s|%\d+s', repl, text)
    return clean, placeholders

def restore_placeholders(text, replacements):
    for i, ph in enumerate(replacements):
        text = text.replace(f"__PH{i}__", ph, 1)
    return text

def main():
    path = Path(__file__).parent.parent / "assets/translations/localizable.json"
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    en = data.get("en", {})
    if not en:
        print("No 'en' section found")
        return

    keys = list(en.keys())
    values = [str(en[k]) for k in keys]
    prepped = []
    placeholders_map = []
    for v in values:
        if not v or not v.strip():
            prepped.append("")
            placeholders_map.append([])
        else:
            clean, phs = preserve_placeholders(v)
            prepped.append(clean)
            placeholders_map.append(phs)

    translator = GoogleTranslator(source='en', target='es')
    es = {}
    for i in range(0, len(keys), BATCH_SIZE):
        batch_keys = keys[i:i+BATCH_SIZE]
        batch_texts = [prepped[j] for j in range(i, min(i+BATCH_SIZE, len(keys)))]
        batch_texts = [t if t.strip() else " " for t in batch_texts]
        try:
            translated = translator.translate_batch(batch_texts)
            if not isinstance(translated, list):
                translated = [translated]
            for j, key in enumerate(batch_keys):
                idx = i + j
                orig = values[idx]
                if not orig or not orig.strip():
                    es[key] = orig
                else:
                    t = translated[j] if j < len(translated) else orig
                    phs = placeholders_map[idx]
                    es[key] = restore_placeholders(t or orig, phs)
        except Exception as e:
            print(f"Batch {i//BATCH_SIZE} error: {e}")
            for j, key in enumerate(batch_keys):
                es[key] = values[i + j]
        print(f"  {min(i+BATCH_SIZE, len(keys))}/{len(keys)}...")
        time.sleep(0.5)

    data["es"] = es
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"Done. Added {len(es)} Spanish entries.")

if __name__ == "__main__":
    main()
