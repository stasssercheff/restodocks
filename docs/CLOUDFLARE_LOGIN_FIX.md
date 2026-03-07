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
| SUPABASE_ANON_KEY = anon key из Supabase (Dashboard → API) |

## 2. Retry deployment

После правок в Variables: **Deployments** → последний деплой → **⋯** → **Retry deployment**

## 3. Очистка кэша

**Settings** → **Builds** → **Clear build cache** → **Retry deployment**

## 4. Проверка в браузере

Открой консоль (F12) → вкладка Console. При загрузке страницы:
- `url=https://osglfptwbuqq...` — Prod, всё верно
- `url=https://osglfptwbuqq...` — Prod Supabase

## 5. Supabase: Redirect URLs + API CORS

**Authentication** → **URL Configuration** → **Redirect URLs** — должны быть:
```
https://restodocks.com
https://restodocks.com/**
https://www.restodocks.com
https://www.restodocks.com/**
https://restodocks-2u8.pages.dev
https://restodocks-2u8.pages.dev/**
https://restodocks.pages.dev
```

**Site URL** = `https://restodocks.com`

**Project Settings** → **API** — если есть **CORS / Allowed Origins**, добавь:
`https://restodocks.com`, `https://www.restodocks.com`

---

## 6. Отладка: если restodocks.com всё равно не входит

1. Открой restodocks.com → F12 → **Network**
2. Попробуй войти
3. Найди запрос к `auth/v1/token` или `token`
4. Статус:
   - **CORS error** / (blocked) — Supabase не разрешает origin restodocks.com
   - **400/401** — открой ответ (Response): там текст ошибки Supabase
5. Пришли результат — по нему можно понять причину
