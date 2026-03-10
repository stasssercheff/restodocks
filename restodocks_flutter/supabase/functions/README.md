# Edge Functions для ИИ (Restodocks)

**Каскад провайдеров:** Groq (быстро, free) → Gemini → GigaChat → OpenAI. При ошибке одного пробуем следующий. Задачи с картинками (чек, ТТК из фото) — только **OpenAI**.

## Секреты и провайдер

- **GigaChat (приоритет на старте, бесплатный лимит):**  
  В [личном кабинете GigaChat](https://developers.sber.ru/studio/workspaces/) создайте проект → Настройки API → «Получить ключ». Скопируйте **Authorization key** (это Base64 от `ClientID:ClientSecret`). Задайте секрет:
  ```bash
  supabase secrets set GIGACHAT_AUTH_KEY=<ваш Base64-ключ>
  ```
  Тогда все текстовые функции будут использовать GigaChat без оплаты (в пределах лимита).

- **OpenAI (опционально, для картинок или если GigaChat не задан):**
  ```bash
  supabase secrets set OPENAI_API_KEY=sk-your-openai-key
  ```
  Нужен для: распознавание чека по фото, ТТК по фото. Если задан только OpenAI — текстовые задачи тоже пойдут в OpenAI (платно).

- **Google Gemini (бесплатный tier, ключ без карты):**
  Ключ в [aistudio.google.com](https://aistudio.google.com) → Get API key. Затем:
  ```bash
  supabase secrets set GEMINI_API_KEY=ваш-ключ-gemini
  ```
  Текстовые задачи пойдут в Gemini, если не задан GigaChat (или задан `AI_PROVIDER=gemini`).

- **Claude (Anthropic, платно):**
  ```bash
  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
  supabase secrets set AI_PROVIDER=claude
  ```

- **Groq (быстро, free tier):**
  Ключ в [console.groq.com](https://console.groq.com):
  ```bash
  supabase secrets set GROQ_API_KEY=gsk_...
  ```
  По умолчанию первый в каскаде — самый быстрый.

- **Принудительно выбрать провайдера:**
  ```bash
  supabase secrets set AI_PROVIDER=groq   # или gemini, gigachat, openai, claude
  ```
  По умолчанию каскад: Groq → Gemini → GigaChat → OpenAI → Claude (при ошибке пробуем следующий).

- **Google Cloud Translation API (для переводов продуктов, ТТК):**
  1. [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Enable **Cloud Translation API**
  2. Credentials → Create API key
  3. Добавь в Supabase:
  ```bash
  supabase secrets set GOOGLE_TRANSLATE_API_KEY=ваш-api-key
  ```
  Если секрет не задан — переводы идут через MyMemory (fallback, ограниченный лимит).

## Деплой

1. Установите [Supabase CLI](https://supabase.com/docs/guides/cli).
2. В корне проекта (рядом с `restodocks_flutter`):
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```
3. Задайте хотя бы один из секретов (см. выше):
   - для бесплатного старта: `GROQ_API_KEY` или `GEMINI_API_KEY` или `GIGACHAT_AUTH_KEY`;
   - для фото: `OPENAI_API_KEY`.
4. Деплой всех функций:
   ```bash
   cd restodocks_flutter
   supabase functions deploy ai-generate-checklist
   supabase functions deploy ai-recognize-receipt
   supabase functions deploy ai-recognize-tech-card
   supabase functions deploy ai-recognize-tech-cards-batch
   supabase functions deploy ai-parse-tech-cards-pdf
   supabase functions deploy ai-recognize-product
   supabase functions deploy ai-refine-nutrition
   supabase functions deploy ai-verify-product
   supabase functions deploy save-order-document
   supabase functions deploy translate-text
   ```
   Или из папки, где лежит `supabase/`:
   ```bash
   supabase functions deploy ai-generate-checklist --project-ref YOUR_REF
   # ... и т.д.
   ```

## Функции

| Функция | Назначение | Провайдер по умолчанию |
|--------|------------|------------------------|
| `ai-generate-checklist` | Генерация чеклиста по запросу | GigaChat / OpenAI (текст) |
| `ai-recognize-receipt` | Распознавание чека по фото | только OpenAI (vision) |
| `ai-recognize-tech-card` | ТТК по фото или по таблице (Excel), одна карточка | Фото: OpenAI; таблица: GigaChat/OpenAI |
| `ai-recognize-tech-cards-batch` | ТТК из одного документа Excel — все карточки разом | GigaChat / OpenAI (текст) |
| `ai-parse-tech-cards-pdf` | ТТК из PDF (извлечение текста + парсинг) | Groq / Gemini / OpenAI (текст) |
| `ai-recognize-product` | Нормализация названия, категория, единица | GigaChat / OpenAI |
| `ai-refine-nutrition` | КБЖУ по названию продукта | GigaChat / OpenAI |
| `ai-verify-product` | Верификация продукта (цена, КБЖУ, название) | GigaChat / OpenAI |
| `save-order-document` | Сохранение заказа во входящие с ценами из БД (Edge Function, без AI) | — |
| `translate-text` | Перевод текста (продукты, ТТК) | Google Cloud Translation API |

## Локальный запуск (опционально)

**Docker не нужен для деплоя** — `supabase functions deploy` выполняет сборку в облаке. Docker требуется только для `supabase functions serve` (локальная отладка). Если видите «Docker is not running» — можно игнорировать, деплой через GitHub Actions или `supabase deploy` работает без Docker.

```bash
supabase functions serve ai-generate-checklist --env-file .env.local
```

В `.env.local` (хотя бы один):
```
GIGACHAT_AUTH_KEY=<Base64-ключ из личного кабинета GigaChat>
# и/или для фото и fallback:
OPENAI_API_KEY=sk-...
```

## Приложение

Flutter-клиент вызывает функции через `Supabase.instance.client.functions.invoke('ai-generate-checklist', body: {...})`.  
Провайдер по умолчанию: `AiServiceSupabase()`.
