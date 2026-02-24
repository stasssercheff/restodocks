# Настройка Storage для фото сотрудников

## Ошибка «Bucket not found»

Если при загрузке фото в личном кабинете появляется ошибка:
```
Ошибка загрузки: StorageException(message: Bucket not found, statusCode: 404, error: Bucket not found)
```

значит bucket `avatars` ещё не создан в Supabase Storage.

## Решение: создать bucket вручную

1. Откройте [Supabase Dashboard](https://supabase.com/dashboard)
2. Выберите проект Restodocks
3. В левом меню: **Storage** → **New bucket**
4. Укажите:
   - **Name:** `avatars`
   - **Public bucket:** включить (чтобы фото были доступны по публичному URL)
5. Нажмите **Create bucket**

После этого загрузка фото в профиле должна работать.

## Политики доступа (опционально)

Для ограничения доступа можно настроить RLS в Storage:

- **INSERT** — разрешить аутентифицированным пользователям загружать файлы
- **SELECT** — разрешить всем читать (для публичного bucket)

В Dashboard: Storage → avatars → Policies.
