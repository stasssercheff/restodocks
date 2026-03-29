# Вход не работает на Cloudflare Pages — чеклист

## restodocks.com: прямой URL Supabase

Приложение использует **прямой URL Supabase** для всех доменов (restodocks.com, restodocks-2u8.pages.dev, restodocks.pages.dev). Для работы входа **restodocks.com** должен быть в Supabase Auth → Redirect URLs (см. п. 5 ниже). Прокси больше не используется.

## 0a. Кастомный домен: restodocks.com vs restodocks-2u8.pages.dev

Если вход работает на `restodocks-2u8.pages.dev`, но **не работает на restodocks.com** — проверь настройки домена:

1. **Cloudflare Pages** → проект **restodocks** → **Custom domains**
   - Должны быть оба: `restodocks.com` и `restodocks-2u8.pages.dev`
   - Оба должны вести на один и тот же deployment (последний Production build)
   - Статус: **Active** (без предупреждений)

2. **Один deployment для обоих URL** — restodocks.com и restodocks-2u8.pages.dev должны отдавать одинаковый билд. Если restodocks.com добавлен в другой проект или с другой конфигурацией — будет разное поведение.

3. **Supabase Auth** — Origin `https://restodocks.com` должен быть разрешён. Добавь с wildcard:
   - **Site URL** = `https://restodocks.com`
   - **Redirect URLs** (должны быть):
     - `https://restodocks.com`
     - `https://restodocks.com/**`
     - `https://www.restodocks.com`
     - `https://www.restodocks.com/**`
     - `https://restodocks-2u8.pages.dev`
     - `https://restodocks-2u8.pages.dev/**`

4. **DNS (Namecheap и т.п.)** — apex `restodocks.com` должен указывать на Cloudflare Pages:
   - Либо A-записи на IP Cloudflare (из Custom domains)
   - Либо редирект restodocks.com → www.restodocks.com, а www → CNAME на `restodocks-2u8.pages.dev`
   - Важно: если apex редиректит на www, пользователь окажется на www; оба домена должны быть в Supabase Redirect URLs

5. **Cloudflare zone (если домен на Cloudflare)** — Page Rules, Redirect Rules: нет ли правил, которые меняют заголовки или редиректы для restodocks.com.

## 0. Production: использовать cloudflare-build-prod.sh

Для **основного** сайта в Build settings задайте: **Build command** = `./cloudflare-build-prod.sh`

Этот скрипт всегда использует Production Supabase. Variables не нужны.

---

## 1. Variables и Environment (только для Beta)

Cloudflare Pages → проект → **Settings** → **Variables and Secrets**

- Переменные должны быть заданы для **обоих** Environment: **Production** и **Preview**
- Проверь scope: отметь **Production** и **Preview**

| Prod и Beta |
|-------------|
| SUPABASE_URL = `https://osglfptwbuqqmqunttha.supabase.co` |
| SUPABASE_ANON_KEY = anon key из Supabase → Settings → API Keys (anon public) |

## 2. Retry deployment

После правок в Variables: **Deployments** → последний деплой → **⋯** → **Retry deployment**

## 3. Очистка кэша

**Settings** → **Builds** → **Clear build cache** → **Retry deployment**

## 4. Проверка в браузере

Открой консоль (F12) → вкладка Console. При загрузке страницы:
- `url=https://osglfptwbuqq...` — Prod, всё верно
- `url=https://osglfptwbuqq...` — Prod Supabase

## 5. Supabase: Redirect URLs + API CORS

**Authentication** → **URL Configuration** → **Redirect URLs** — должны быть (включая wildcard для Pages):
```
https://restodocks.com
https://restodocks.com/**
https://www.restodocks.com
https://www.restodocks.com/**
https://restodocks-2u8.pages.dev
https://restodocks-2u8.pages.dev/**
https://restodocks.pages.dev
https://restodocks.pages.dev/**
```

**Site URL** = `https://restodocks.com`

**CORS / Allowed Origins** (если есть): в новых версиях дашборда Supabase настройки CORS могут быть в **Settings** → **API** или **Data API**. Добавь домены:
`https://restodocks.com`, `https://www.restodocks.com`, `https://restodocks.pages.dev`, `https://restodocks-2u8.pages.dev`.  
Если отдельного поля нет — Redirect URLs выше обычно достаточно для Auth.

---

## 6. 401 от authenticate-employee

Если в Network видишь **401** на `authenticate-employee` (даже при правильном пароле):
- Может быть **proxy/маршрутизация** — Cloudflare или сеть обрывает первый запрос. Приложение делает retry, один из запросов доходит.
- Проверь: **Configuration Rule Bypass cache** (см. [CLOUDFLARE_RESTODOCKS_COM_FIX.md](CLOUDFLARE_RESTODOCKS_COM_FIX.md)).
- Тот же логин работает на restodocks-2u8.pages.dev? Если да — добавь restodocks.com в Supabase (п. 5).

## 7. Отладка: auth/v1/token

1. Открой restodocks.com → F12 → **Network**
2. Попробуй войти
3. Найди запрос к `auth/v1/token` или `token`
4. Статус:
   - **CORS error** / (blocked) — добавь restodocks.com в Auth Redirect URLs и Site URL (п. 5)
   - **400** "Invalid login credentials" — неверный пароль
5. Пришли результат — по нему можно понять причину

## 8. Статус 522 на `auth/v1/token` и «CORS» в консоли

**522** (Cloudflare) = до бэкенда Auth **не дошли вовремя** или соединение оборвалось. Это **не баг Flutter** и не «исправляется» сменой таймаута на кнопке входа: запрос падает **до** успешного ответа Supabase.

Браузер часто пишет ещё и **«Origin … is not allowed by Access-Control-Allow-Origin»**: при ошибочном/пустом ответе (522) заголовки CORS могут не совпасть с ожиданием — сначала устраняют **522**, а не только Redirect URLs.

Что проверить:

1. **Supabase Dashboard** → проект → не на паузе (free tier), нет инцидентов ([status.supabase.com](https://status.supabase.com)).
2. С машины: `curl -sS -o /dev/null -w "%{http_code}" https://osglfptwbuqqmqunttha.supabase.co/auth/v1/health` — ожидается **200** (или хотя бы не таймаут).
3. **Authentication** → **URL Configuration** — в Redirect URLs есть `https://restodocks.pages.dev` и `https://restodocks.pages.dev/**` (п. 5 выше).
4. **500 на `authenticate-employee`** — **Edge Functions** → `authenticate-employee` → **Logs** по времени запроса; там будет стек/причина (БД, Auth admin API, и т.д.).

Пока **522** на `…supabase.co/auth/v1/token` не исчезнет, вход с сайта не заработает — независимо от версии приложения в репозитории.
