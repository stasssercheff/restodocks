# Настройка Storage для фото сотрудников

## Ошибка «Bucket not found» (404)

Если при загрузке фото появляется:
```
Ошибка загрузки: StorageException(message: Bucket not found, statusCode: 404)
```

создайте bucket вручную: **Storage** → **New bucket** → Name: `avatars`, Public bucket: включить → **Create bucket**.

## Ошибка RLS «new row violates row-level security policy» (403)

Если появляется:
```
Ошибка загрузки: StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)
```

примените миграцию `supabase/migrations/20260226120000_storage_avatars_rls.sql` в Supabase SQL Editor (или через `supabase db push`).
