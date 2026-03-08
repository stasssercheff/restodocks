# Деплой Restodocks на Cloudflare Pages

## 1. Подключить репозиторий

1. [Cloudflare Dashboard](https://dash.cloudflare.com) → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. Выберите репозиторий **Restodocks** (или `restodocks_flutter`).
3. **Root directory**: `restodocks_flutter` (если репо — родительская папка) или оставьте пустым.

## 2. Настройка сборки

| Параметр | Значение |
|----------|----------|
| **Build command** | `bash cloudflare-build.sh` |
| **Build output directory** | `build/web` |
| **Root directory** | `restodocks_flutter` (если нужно) |

Скрипт `cloudflare-build.sh` устанавливает Flutter, генерирует артефакт из env и создаёт `_redirects`, `_headers`, `_routes.json` для SPA и кэширования.

## 3. Переменные окружения

**Settings** → **Environment variables** (Production и Preview):

| Key | Value |
|-----|-------|
| `SUPABASE_URL` | `https://....supabase.co` |
| `SUPABASE_ANON_KEY` | `eyJ...` (anon key) |

Можно использовать `NEXT_PUBLIC_SUPABASE_URL` и `NEXT_PUBLIC_SUPABASE_ANON_KEY` — скрипт их подхватит.

## 4. Workflow веток (Beta / Prod)

- **Beta**: Production branch = `staging`. Сюда пушим при разработке.
- **Prod**: Production branch = `main`. Только при релизе.
- В **Preview deployments** выберите **None**, чтобы не тратить сборки на превью.

Релиз в Prod: `git checkout main && git merge staging && git push origin main`.

## 5. Подключение своего домена

1. **Cloudflare** → Workers & Pages → проект → **Custom domains**.
2. Добавьте `restodocks.com` и `www.restodocks.com`.
3. Cloudflare предложит DNS‑записи (обычно уже настроено, если DNS на Cloudflare).

## 6. Ошибки сборки

1. **ERROR: Set SUPABASE_URL and SUPABASE_ANON_KEY** — добавьте переменные в Environment variables.
2. **Build output directory not found** — убедитесь, что `cloudflare-build.sh` создаёт `build/web`.
3. **404 при навигации** — проверьте `_redirects`: `/*  /index.html  200`.

## 7. Supabase Auth

Добавьте в Supabase → Authentication → URL Configuration → Redirect URLs:
- `https://restodocks.pages.dev`
- `https://restodocks.pages.dev/**`
- `https://*.pages.dev`
- Ваши кастомные домены (`restodocks.com`, `www.restodocks.com`).

Подробнее: `SUPABASE_AUTH_URL_CONFIG.md`.
