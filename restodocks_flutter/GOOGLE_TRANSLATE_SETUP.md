# Google Cloud Translation API — настройка

Переводы продуктов и ТТК на сайте Restodocks используют Google Cloud Translation API как основной источник. При отсутствии ключа или при ошибке — fallback на MyMemory (ограниченный лимит).

## Шаги

1. **Google Cloud Console** → [console.cloud.google.com](https://console.cloud.google.com)
2. **APIs & Services** → **Library** → найдите **Cloud Translation API** → **Enable**
3. **APIs & Services** → **Credentials** → **Create credentials** → **API key**
4. (Рекомендуется) Ограничьте ключ: **APIs** → только **Cloud Translation API**; **Application restrictions** — по необходимости (можно оставить без ограничений для тестов)
5. Добавьте секрет в Supabase:
   ```bash
   npx supabase secrets set GOOGLE_TRANSLATE_API_KEY=ваш-api-key
   ```
6. Задеплойте Edge Function:
   ```bash
   npx supabase functions deploy translate-text --project-ref ВАШ_REF
   ```

## Лимиты (2024)

- Бесплатно: ~500 000 символов в месяц (зависит от квот проекта)
- При превышении — платное использование
- Настройте Budget в Google Cloud, чтобы получать уведомления о тратах

## Отключение Google Translate

В коде: `TranslationService.useGoogleTranslate = false` — тогда будет использоваться только MyMemory.
