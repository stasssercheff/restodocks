# Настройка бета-деплоя (staging → Beta)

Основной деплой: **Cloudflare Pages** (см. [CLOUDFLARE_PAGES_DEPLOY.md](CLOUDFLARE_PAGES_DEPLOY.md)).  
Beta смотрит ветку `staging`. Prod смотрит `main`. Не пушить в main до релиза.

## 1. Включить GitHub Actions

1. Откройте репозиторий → **Settings** → **Actions** → **General**
2. В блоке **Actions permissions** выберите **Allow all actions and reusable workflows**
3. Сохраните (**Save**)

## 2. Секреты GitHub (для Prod и Edge Functions)

**Settings** → **Secrets and variables** → **Actions**

| Секрет | Использование |
|--------|---------------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare Pages (Prod), Admin Workers |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare (Dashboard → Overview) |
| `SUPABASE_URL` | Prod deploy, Edge Functions |
| `SUPABASE_ANON_KEY` | Prod deploy |
| `SUPABASE_ACCESS_TOKEN` | Edge Functions, supabase-add-cloudflare-urls |

## 3. Beta

Beta деплоится автоматически при push в `staging` — Cloudflare Pages (проект Restodocks Beta, Production branch = staging). Настройка в [CLOUDFLARE_PAGES_DEPLOY.md](CLOUDFLARE_PAGES_DEPLOY.md).

## 4. Admin

Admin (beta-admin) — Cloudflare Workers. При push в `main` деплоится workflow **Deploy Admin to Cloudflare Workers**.  
Настройка: [CLOUDFLARE_ADMIN_DEPLOY.md](CLOUDFLARE_ADMIN_DEPLOY.md).

## Миграции Supabase

**Важно:** без миграций чеклисты и сообщения не работают (PGRST204, PGRST205).

- **CLI:** `cd restodocks_flutter && supabase db push`
- **Вручную:** Supabase Dashboard → SQL Editor → `docs/CHECKLIST_SETUP.sql` или `supabase/migrations/`
- **После миграций:** Settings → General → **Restart project**
