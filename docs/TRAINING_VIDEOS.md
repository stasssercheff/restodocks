# Обучающие видео

Видео отдаются по IP: **российские** получают ссылку на Supabase Storage (сокращаем трафик), **остальные** — на YouTube.

## Загрузка видео в Supabase

1. Применить миграцию (если ещё не применена): `supabase/migrations/20260326120000_storage_training_videos.sql`
2. Supabase Dashboard → Storage → bucket `training_videos`
3. Загрузить файлы с именами вида `goZ20v6DV2s.mp4` (YouTube video ID + `.mp4`)

Соответствие ID → видео см. в `restodocks_flutter/supabase/functions/get-training-video-url/index.ts` (YOUTUBE_MAP).

**Разбитые видео (>100 МБ):** если видео порезано на части — отдельные ID:
- `VFSGL0Zj7fc.mp4` — Инвентаризации IIKO слияние_1
- `WQruFDlDQ.mp4` — Инвентаризации IIKO слияние_2

## Деплой Edge Function

```bash
cd restodocks_flutter
npx supabase functions deploy get-training-video-url --project-ref osglfptwbuqqmqunttha
```

## GeoIP

Используется ip-api.com (бесплатно). Лимит ~45 запросов/мин. При превышении или ошибке — fallback на YouTube.
