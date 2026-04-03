# Rate Limiting в Cloudflare для RestoDocks

Ограничение запросов с одного IP — защита от ботов и скрапинга. Обычный повар/официант столько не нажмёт, а бот быстро «отлетит».

---

## Быстрая настройка (≈5 минут)

### 1. Открой Cloudflare

1. Зайди в [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Выбери зону **restodocks.com** (или Beta, если нужен тестовый домен)

### 2. Перейди в Rate Limiting

- **Новый интерфейс:** Security → **Security rules** → Create rule → **Rate limiting rules**
- **Старый интерфейс:** Security → WAF → **Rate limiting rules** → Create rule

### 3. Создай правило

| Поле | Значение |
|------|----------|
| **Rule name** | `RestoDocks — 100 req/min per IP` |
| **If incoming requests match…** | Оставь `(http.request.uri.path contains "/")` — правило для всего сайта |
| **With the same characteristics** | **IP Address** (счётчик по IP) |
| **When rate exceeds** | **100** requests per **1** minute |
| **Then take action** | **Block** |
| **Duration** | 10 sec (на Free — только этот вариант; на Pro+ можно 1 min) |

### 4. Deploy

Нажми **Deploy** — правило начнёт работать сразу.

---

## Рекомендуемые значения

| Сценарий | Запросов/мин | Период блокировки |
|----------|--------------|-------------------|
| **Строгий** | 60 | 10 sec (Free) / 1 min (Pro+) |
| **Стандарт** (оптимально) | 100 | 10 sec (Free) / 1 min (Pro+) |
| **Мягкий** | 150–200 | 10 sec (Free) / 1 min (Pro+) |

Для RestoDocks разумно начать с **100 запросов в минуту**.

**Free план:** Duration только 10 sec — всё равно эффективно, бот будет постоянно упираться в блокировку.

---

## Нужно для обеих зон?

Да. Настрой Rate Limiting отдельно для:
- **restodocks.com** (Prod — main)
- **Beta** (если есть отдельная зона/домен)

Либо на уровне аккаунта, если используешь Account-level WAF.

---

## Как проверить

1. Открой DevTools → Network
2. Сделай 101+ запросов за минуту (можно скриптом или много раз обновляя страницу)
3. Должен вернуться **429 Too Many Requests**

Обычная работа приложения это не затронет.

---

## Supabase Edge (`*.supabase.co/functions/v1/...`)

Клиент (Flutter / web) чаще всего ходит **напрямую** в Supabase по URL вида `https://<project>.supabase.co/functions/v1/...`. Эти запросы **не проходят** через зону Cloudflare `restodocks.com`, поэтому правила rate limiting и WAF выше **не защищают** Edge Functions.

Что делать:

| Мера | Где |
|------|-----|
| Лимиты в коде функций | Уже есть на части эндпоинтов (`enforceRateLimit`, лимиты на AI/почту в `restodocks_flutter/supabase/functions/`) |
| Настройки проекта Supabase | Dashboard → Project → настройки API / abuse (актуальный UI см. в документации Supabase) |
| Отдельные жёсткие лимиты | Дополнительные правила в Cloudflare имеют смысл только если трафик к API идёт через **свой домен/прокси** к Supabase (не стандартная схема) |

Рекомендуемые отдельные лимиты на стороне CF **для сайта** по путям вроде `/api/*` (если есть) — по-прежнему полезны; для **прямого Supabase** опирайтесь на код функций + мониторинг 429/401 в логах.
