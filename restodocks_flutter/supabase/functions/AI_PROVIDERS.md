# Распределение AI-провайдеров по задачам

Каждая группа задач может использовать свой провайдер (или каскад). Если env-переменная не задана — используется каскад по всем доступным ключам.

## Переменные окружения

| Переменная | Задача | Edge Functions |
|------------|--------|----------------|
| `AI_PROVIDER_TTK` | Legacy общий для ТТК | fallback для ttk_parse/ttk_create |
| `AI_PROVIDER_TTK_PARSE` | Парсинг ТТК | ai-parse-tech-cards-pdf, ai-recognize-tech-card, ai-recognize-tech-cards-batch |
| `AI_PROVIDER_TTK_CREATE` | Создание ТТК с ИИ | поток генерации рецептов/ТТК |
| `AI_PROVIDER_NUTRITION` | КБЖУ | ai-refine-nutrition |
| `AI_PROVIDER_PRODUCT` | Продукты | ai-normalize-product-names, ai-find-duplicates, ai-verify-product, ai-recognize-product, ai-parse-product-list |
| `AI_PROVIDER_CHECKLIST` | Чеклисты | ai-generate-checklist |
| `AI_PROVIDER` | Глобально (если задан — для всех, если не задан — каскад) | — |

## Порядок каскада (при отсутствии явного провайдера)

1. Groq  
2. Gemini  
3. GigaChat  
4. OpenRouter  
5. Mistral  
6. Cerebras  
7. OpenAI  
8. Claude  

## Рекомендации по назначению провайдеров

| Группа | Рекомендация | Причина |
|--------|--------------|---------|
| **TTK** | Groq или каскад | Тяжёлые запросы, много токенов. Groq быстрый, free tier 500k/мес |
| **Nutrition** | OpenRouter/Cerebras | Лёгкие запросы, можно пустить на бесплатные модели |
| **Product** | GigaChat/OpenRouter | Частые мелкие запросы, много — распределить по free tiers |
| **Checklist** | Gemini или каскад | Средний объём, нужна стабильность |

## Пример настройки в Supabase Secrets

Распределить нагрузку:

- `AI_PROVIDER_TTK_PARSE` = `groq` — парсинг ТТК через Groq
- `AI_PROVIDER_TTK_CREATE` = `deepseek` — генерация новых ТТК через DeepSeek
- `AI_PROVIDER_NUTRITION` = `openrouter` — КБЖУ через OpenRouter
- `AI_PROVIDER_PRODUCT` = `gigachat` — продукты через GigaChat
- `AI_PROVIDER_CHECKLIST` не задавать — каскад для чеклистов

Или оставить все переменные пустыми — везде будет каскад (Groq → Gemini → …).
