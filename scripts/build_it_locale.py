#!/usr/bin/env python3
"""
Fill localizable.json \"it\" with the same keys as \"es\" (≈1735), using ES→IT MT.
Preserves existing manual strings in \"it\" (e.g. tour_tile_*).

Run from repo root: python3 scripts/build_it_locale.py
Resume: re-run; checkpoint is scripts/.it_locale_checkpoint.json
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("pip install deep-translator", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "restodocks_flutter/assets/translations/localizable.json"
CHECKPOINT = Path(__file__).resolve().parent / ".it_locale_checkpoint.json"

BATCH_SIZE = 12
SLEEP_BETWEEN_BATCHES = 0.35


def load_checkpoint() -> dict[str, str]:
    if not CHECKPOINT.is_file():
        return {}
    return json.loads(CHECKPOINT.read_text(encoding="utf-8"))


def save_checkpoint(cp: dict[str, str]) -> None:
    CHECKPOINT.write_text(json.dumps(cp, ensure_ascii=False, indent=2), encoding="utf-8")


def translate_batch(translator: GoogleTranslator, texts: list[str]) -> list[str]:
    last_err: Exception | None = None
    for attempt in range(3):
        try:
            out = translator.translate_batch(texts)
            if len(out) != len(texts):
                raise RuntimeError(f"len {len(out)} != {len(texts)}")
            return out
        except Exception as e:
            last_err = e
            time.sleep(1.0 * (attempt + 1))
    # Per-string fallback
    out: list[str] = []
    for t in texts:
        for attempt in range(3):
            try:
                out.append(translator.translate(t))
                break
            except Exception as e:
                last_err = e
                time.sleep(0.4 * (attempt + 1))
        else:
            out.append(t)  # keep Spanish as last resort
        time.sleep(0.08)
    if last_err:
        print(f"batch had errors, used fallback: {last_err}", file=sys.stderr)
    return out


def main() -> None:
    translator = GoogleTranslator(source="es", target="it")
    data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    es: dict[str, str] = data["es"]
    manual_it: dict[str, str] = dict(data.get("it") or {})
    es_keys: list[str] = list(es.keys())

    cp = load_checkpoint()
    new_it: dict[str, str] = {}

    pending_keys: list[str] = []
    pending_texts: list[str] = []

    def flush() -> None:
        nonlocal pending_keys, pending_texts, cp
        if not pending_keys:
            return
        keys = pending_keys
        texts = pending_texts
        pending_keys = []
        pending_texts = []
        translated = translate_batch(translator, texts)
        for k, v in zip(keys, translated):
            new_it[k] = v
            cp[k] = v
        save_checkpoint(cp)
        time.sleep(SLEEP_BETWEEN_BATCHES)

    total = len(es_keys)
    for i, k in enumerate(es_keys):
        if k in manual_it:
            new_it[k] = manual_it[k]
            continue
        if k in cp:
            new_it[k] = cp[k]
            continue
        pending_keys.append(k)
        pending_texts.append(es[k])
        if len(pending_keys) >= BATCH_SIZE:
            flush()
        if (i + 1) % 250 == 0:
            print(f"... {i + 1}/{total}", file=sys.stderr)
    flush()

    if len(new_it) != len(es_keys):
        missing = set(es_keys) - set(new_it)
        raise SystemExit(f"missing keys: {sorted(missing)[:20]!r} ...")

    order = {k: j for j, k in enumerate(es_keys)}
    data["it"] = dict(sorted(new_it.items(), key=lambda kv: order[kv[0]]))

    JSON_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {len(data['it'])} keys to it. Checkpoint: {CHECKPOINT}", file=sys.stderr)


if __name__ == "__main__":
    main()
