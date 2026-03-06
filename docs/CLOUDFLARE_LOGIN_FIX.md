# Вход не работает на Cloudflare Pages — чеклист

## 1. Variables и Environment

Cloudflare Pages → проект → **Settings** → **Variables and Secrets**

- Переменные должны быть заданы для **обоих** Environment: **Production** и **Preview**
- Проверь scope: отметь **Production** и **Preview**

| Prod-сайт (основной) | Beta (демо) |
|----------------------|-------------|
| SUPABASE_URL = `https://osglfptwbuqqmqunttha.supabase.co` | `https://kzhaezanjttvnqkgpxnh.supabase.co` |
| SUPABASE_ANON_KEY = anon key из Production | anon key из Staging |

## 2. Retry deployment

После правок в Variables: **Deployments** → последний деплой → **⋯** → **Retry deployment**

## 3. Очистка кэша

**Settings** → **Builds** → **Clear build cache** → **Retry deployment**

## 4. Проверка в браузере

Открой консоль (F12) → вкладка Console. При загрузке страницы:
- `url=https://osglfptwbuqq...` — Prod, всё верно
- `url=https://kzhaezanjttv...` — Staging, для основного сайта должно быть Prod

## 5. Supabase Auth Redirect URLs

Supabase Dashboard → **Authentication** → **URL Configuration** → **Redirect URLs**

Должны быть добавлены:
```
https://restodocks.pages.dev
https://restodocks-2u8.pages.dev
https://www.restodocks.com
https://restodocks.com
```
