# Edge Functions для ИИ (Restodocks)

**На старте приоритет — бесплатные сервисы.** Текстовые задачи (чеклист, продукт, КБЖУ, верификация, ТТК из Excel) идут через **GigaChat** (1 млн токенов/год бесплатно для физлиц), если задан `GIGACHAT_AUTH_KEY`. Задачи с картинками (чек из фото, ТТК из фото) — только **OpenAI** (платно).

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

- **Принудительно выбрать провайдера:**
  ```bash
  supabase secrets set AI_PROVIDER=gigachat   # или openai, gemini, claude
  ```
  По умолчанию приоритет: GigaChat → Gemini → Claude → OpenAI (по первому заданному ключу).

## Деплой

1. Установите [Supabase CLI](https://supabase.com/docs/guides/cli).
2. В корне проекта (рядом с `restodocks_flutter`):
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```
3. Задайте хотя бы один из секретов (см. выше):
   - для бесплатного старта: `GIGACHAT_AUTH_KEY`;
   - для фото: `OPENAI_API_KEY`.
4. Деплой всех функций:
   ```bash
   cd restodocks_flutter
   supabase functions deploy ai-generate-checklist
   supabase functions deploy ai-recognize-receipt
   supabase functions deploy ai-recognize-tech-card
   supabase functions deploy ai-recognize-tech-cards-batch
   supabase functions deploy ai-recognize-product
   supabase functions deploy ai-refine-nutrition
   supabase functions deploy ai-verify-product
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
| `ai-recognize-product` | Нормализация названия, категория, единица | GigaChat / OpenAI |
| `ai-refine-nutrition` | КБЖУ по названию продукта | GigaChat / OpenAI |
| `ai-verify-product` | Верификация продукта (цена, КБЖУ, название) | GigaChat / OpenAI |

## Локальный запуск (опционально)

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
