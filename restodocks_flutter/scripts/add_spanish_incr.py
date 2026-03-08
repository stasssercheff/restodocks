#!/usr/bin/env python3
"""Add Spanish incrementally - translates in small batches, saves progress."""
import json
import re
import time
from pathlib import Path
from deep_translator import GoogleTranslator

def preserve_placeholders(text):
    phs = []
    def repl(m):
        phs.append(m.group(0))
        return f"__P{len(phs)-1}__"
    return re.sub(r'\{[^}]+\}|%s|%\d+s', repl, text), phs

def restore(text, phs):
    for i, p in enumerate(phs):
        text = text.replace(f"__P{i}__", p, 1)
    return text

path = Path(__file__).parent.parent / "assets/translations/localizable.json"
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

en = data["en"]
es = data.get("es", {}).copy()
translator = GoogleTranslator(source='en', target='es')
todo = [k for k in en if k not in es or not str(es.get(k, "")).strip()]
print(f"To translate: {len(todo)}")

for i, key in enumerate(todo):
    val = str(en[key])
    if not val.strip():
        es[key] = val
        continue
    try:
        clean, phs = preserve_placeholders(val)
        t = translator.translate(clean[:5000])  # API limit
        es[key] = restore(t or val, phs)
    except:
        es[key] = val
    if (i + 1) % 50 == 0:
        data["es"] = es
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"  {i+1}/{len(todo)} saved")
    time.sleep(0.2)

data["es"] = es
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print(f"Done. es={len(es)}")
