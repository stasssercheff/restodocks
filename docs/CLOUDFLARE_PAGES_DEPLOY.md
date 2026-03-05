# Деплой Restodocks на Cloudflare Pages

При каждом переносе на новый хостинг (Vercel → Netlify → Cloudflare) нужно правильно настроить **одну и ту же базу Supabase** и **добавить домен в Supabase Auth**. Без этого вход срывается с «неверный пароль».

---

## Что обязательно сделать

### 1. Environment Variables в Cloudflare Pages

Cloudflare Pages → проект → **Settings** → **Environment variables** → **Add variable**

| Key | Value | Environment |
|-----|-------|-------------|
| `SUPABASE_URL` | `https://osglfptwbuqqmqunttha.supabase.co` | Production, Preview |
| `SUPABASE_ANON_KEY` | anon key из Supabase Dashboard → Project Settings → API | Production, Preview |

Где взять:
- Supabase Dashboard → ваш проект → **Project Settings** → **API**
- **Project URL** → `SUPABASE_URL`
- **anon public** → `SUPABASE_ANON_KEY`

Берите ключи **из Production проекта**, где лежат данные пользователей. Не из Staging.

### 2. Supabase Auth: добавить новый домен

Без этого Auth может работать некорректно.

1. Supabase Dashboard → **Authentication** → **URL Configuration**
2. В **Redirect URLs** добавьте (если ещё нет):

```
https://restodocks.pages.dev
https://restodocks.pages.dev/
https://*.restodocks.pages.dev
https://*.restodocks.pages.dev/
```

3. **Save**

### 3. Сборка Cloudflare Pages

При подключении репозитория к Cloudflare Pages:

- **Framework preset**: None
- **Build command**: `./cloudflare-build.sh`
- **Build output directory**: `restodocks_flutter/build/web`

Скрипт в корне репо переходит в `restodocks_flutter` и вызывает `./cloudflare-build.sh` оттуда.

### 4. Пересборка после правок env

После добавления/изменения Environment Variables нужно **Clear build cache** и **Retry deployment**, чтобы сборка использовала новые значения.

---

## Контрольный список при переносе хостинга

| Шаг | Действие |
|-----|----------|
| 1 | Задать `SUPABASE_URL` и `SUPABASE_ANON_KEY` в env нового хостинга |
| 2 | Использовать **те же** значения, что и для Production (не Staging) |
| 3 | Добавить новый домен в Supabase → Authentication → URL Configuration → Redirect URLs |
| 4 | Пересобрать проект (очистить кэш, если env менялись) |

---

## Почему «неверный пароль» при переносе

1. **Другая Supabase** — env указывают на Staging или другой проект, где нет этих пользователей.
2. **Пустые env** — сборка упадёт, но если fallback сработал, приложение может использовать старые/дефолтные ключи.
3. **Новый домен не в Redirect URLs** — для части сценариев Auth будет возвращать ошибки.

Данные пользователей не меняются при смене хостинга. Меняется только место, откуда идут запросы. Нужно, чтобы env и Supabase Auth были настроены под новый домен.
