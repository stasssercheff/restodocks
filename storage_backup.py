#!/usr/bin/env python3
"""
Бэкап Supabase Storage — скачивает все бакеты включая вложенные папки.
Нужен service_role ключ: SUPABASE_SERVICE_ROLE_KEY (или SUPABASE_ANON_KEY как fallback).
"""
import os
import sys
import requests
from datetime import datetime

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://osglfptwbuqqmqunttha.supabase.co")
SUPABASE_KEY = (
    os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    or os.getenv("SUPABASE_ANON_KEY")
)

if not SUPABASE_KEY or SUPABASE_KEY == "YOUR_SERVICE_ROLE_KEY_HERE":
    print("❌ SUPABASE_SERVICE_ROLE_KEY не задан в backup_config.env")
    print("   Получи его в Supabase Dashboard → Project Settings → API → service_role")
    sys.exit(1)

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
}

OUTPUT_DIR = os.getenv("STORAGE_BACKUP_DIR", f"storage_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}")


def list_files(bucket: str, prefix: str = "") -> list[str]:
    """Рекурсивно получает все пути файлов в бакете."""
    url = f"{SUPABASE_URL}/storage/v1/object/list/{bucket}"
    payload = {"prefix": prefix, "limit": 1000, "offset": 0}
    resp = requests.post(url, json=payload, headers=HEADERS, timeout=30)
    if resp.status_code != 200:
        print(f"   ⚠️ Ошибка получения списка '{bucket}/{prefix}': {resp.status_code} {resp.text[:200]}")
        return []

    items = resp.json()
    if not isinstance(items, list):
        return []

    paths = []
    for item in items:
        name = item.get("name", "")
        metadata = item.get("metadata")
        if metadata is None:
            # Это папка — рекурсивно обходим
            sub_prefix = f"{prefix}{name}/" if prefix else f"{name}/"
            paths.extend(list_files(bucket, sub_prefix))
        else:
            # Это файл
            file_path = f"{prefix}{name}" if prefix else name
            paths.append(file_path)
    return paths


def download_file(bucket: str, file_path: str, local_dir: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{file_path}"
    resp = requests.get(url, headers=HEADERS, timeout=60, stream=True)
    if resp.status_code != 200:
        print(f"   ❌ Ошибка скачивания {file_path}: {resp.status_code}")
        return False

    local_path = os.path.join(local_dir, file_path.replace("/", os.sep))
    os.makedirs(os.path.dirname(local_path) if os.path.dirname(local_path) else local_dir, exist_ok=True)
    with open(local_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)
    return True


def backup_storage():
    print(f"💾 Бэкап Supabase Storage → {OUTPUT_DIR}")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Получаем список бакетов
    resp = requests.get(f"{SUPABASE_URL}/storage/v1/bucket", headers=HEADERS, timeout=30)
    if resp.status_code != 200:
        print(f"❌ Не удалось получить список бакетов: {resp.status_code} {resp.text[:300]}")
        print("   Возможно, нужен service_role ключ (не anon)")
        sys.exit(1)

    buckets = resp.json()
    if not isinstance(buckets, list) or len(buckets) == 0:
        print("   ℹ️ Бакетов нет или Storage не используется")
        return

    print(f"📂 Найдено бакетов: {len(buckets)}")
    total_files = 0
    total_errors = 0

    for bucket in buckets:
        bucket_name = bucket.get("name", "")
        print(f"\n📦 Бакет: {bucket_name}")
        bucket_dir = os.path.join(OUTPUT_DIR, bucket_name)
        os.makedirs(bucket_dir, exist_ok=True)

        files = list_files(bucket_name)
        if not files:
            print(f"   ℹ️ Бакет пустой")
            continue

        print(f"   Файлов: {len(files)}")
        for file_path in files:
            print(f"   ↓ {file_path}")
            ok = download_file(bucket_name, file_path, bucket_dir)
            if ok:
                total_files += 1
            else:
                total_errors += 1

    print(f"\n✅ Скачано файлов: {total_files}, ошибок: {total_errors}")

    # Архивируем
    import subprocess
    archive = f"{OUTPUT_DIR}.tar.gz"
    subprocess.run(
        ["tar", "-czf", archive, "-C", os.path.dirname(OUTPUT_DIR) or ".", os.path.basename(OUTPUT_DIR)],
        check=True,
    )
    print(f"📦 Архив: {archive}")


if __name__ == "__main__":
    backup_storage()
