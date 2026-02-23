#!/usr/bin/env python3
"""
Скрипт для бэкапа Supabase Storage
"""
import os
import requests
from datetime import datetime
from supabase import create_client

def backup_storage():
    # Конфигурация
    supabase_url = os.getenv('SUPABASE_URL')
    supabase_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')

    if not supabase_url or not supabase_key:
        print("❌ SUPABASE_URL или SUPABASE_SERVICE_ROLE_KEY не установлены")
        return

    # Создаем клиента Supabase
    supabase = create_client(supabase_url, supabase_key)

    # Директория для бэкапа
    backup_dir = f"storage_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    os.makedirs(backup_dir, exist_ok=True)

    print(f"💾 Начинаем бэкап storage в {backup_dir}")

    try:
        # Получаем список бакетов
        buckets_response = supabase.storage.list_buckets()
        buckets = buckets_response if isinstance(buckets_response, list) else []

        print(f"📂 Найдено бакетов: {len(buckets)}")

        for bucket in buckets:
            bucket_name = bucket['name']
            print(f"📦 Обрабатываем бакет: {bucket_name}")

            bucket_dir = os.path.join(backup_dir, bucket_name)
            os.makedirs(bucket_dir, exist_ok=True)

            try:
                # Получаем список файлов в бакете
                files = supabase.storage.from_(bucket_name).list()

                if not files:
                    print(f"   ⚠️ Бакет {bucket_name} пустой")
                    continue

                for file_info in files:
                    if isinstance(file_info, dict) and 'name' in file_info:
                        file_name = file_info['name']
                        file_path = os.path.join(bucket_dir, file_name)

                        print(f"   📄 Скачиваем: {file_name}")

                        # Скачиваем файл
                        file_data = supabase.storage.from_(bucket_name).download(file_name)

                        if file_data:
                            with open(file_path, 'wb') as f:
                                f.write(file_data)
                        else:
                            print(f"   ❌ Ошибка при скачивании {file_name}")

            except Exception as e:
                print(f"   ❌ Ошибка при обработке бакета {bucket_name}: {str(e)}")

        # Создаем архив
        import subprocess
        archive_name = f"{backup_dir}.tar.gz"
        subprocess.run(['tar', '-czf', archive_name, '-C', os.path.dirname(backup_dir), os.path.basename(backup_dir)],
                      check=True)

        print(f"✅ Бэкап storage завершен: {archive_name}")

    except Exception as e:
        print(f"❌ Ошибка при бэкапе storage: {str(e)}")

if __name__ == "__main__":
    backup_storage()