# Edge Functions для ИИ (Restodocks)

Функции вызывают OpenAI API. Нужен ключ **OPENAI_API_KEY**.

## Деплой

1. Установите [Supabase CLI](https://supabase.com/docs/guides/cli).
2. В корне проекта (рядом с `restodocks_flutter`):
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```
3. Задайте секрет (один раз):
   ```bash
   supabase secrets set OPENAI_API_KEY=sk-your-openai-key
   ```
4. Деплой всех функций:
   ```bash
   cd restodocks_flutter
   supabase functions deploy ai-generate-checklist
   supabase functions deploy ai-recognize-receipt
   supabase functions deploy ai-recognize-tech-card
   supabase functions deploy ai-recognize-product
   supabase functions deploy ai-refine-nutrition
   ```
   Или из папки, где лежит `supabase/`:
   ```bash
   supabase functions deploy ai-generate-checklist --project-ref YOUR_REF
   supabase functions deploy ai-recognize-receipt --project-ref YOUR_REF
   # ... и т.д.
   ```

## Функции

| Функция | Назначение |
|--------|------------|
| `ai-generate-checklist` | Генерация чеклиста по запросу (название + пункты) |
| `ai-recognize-receipt` | Распознавание чека по фото (список позиций) |
| `ai-recognize-tech-card` | ТТК по фото карточки или по таблице (rows из Excel) |
| `ai-recognize-product` | Нормализация названия продукта, категория, единица |
| `ai-refine-nutrition` | КБЖУ по названию продукта (fallback) |

## Локальный запуск (опционально)

```bash
supabase functions serve ai-generate-checklist --env-file .env.local
```

В `.env.local`:
```
OPENAI_API_KEY=sk-...
```

## Приложение

Flutter-клиент вызывает функции через `Supabase.instance.client.functions.invoke('ai-generate-checklist', body: {...})`.  
Провайдер по умолчанию: `AiServiceSupabase()`.
