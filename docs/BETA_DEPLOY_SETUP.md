# Настройка бета-деплоя (staging → Vercel)

## 1. Включить GitHub Actions

1. Откройте репозиторий: https://github.com/stasssercheff/restodocks
2. **Settings** → **Actions** → **General**
3. В блоке **Actions permissions** выберите **Allow all actions and reusable workflows**
4. Сохраните (**Save**)

## 2. Добавить Secrets

**Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Добавьте 3 секрета:

| Имя | Откуда взять |
|-----|--------------|
| `STAGING_SUPABASE_URL` | Supabase Dashboard → Project Settings → API → Project URL |
| `STAGING_SUPABASE_ANON_KEY` | Supabase Dashboard → Project Settings → API → anon public |
| `VERCEL_TOKEN` | Vercel → Account Settings → Tokens → Create Token (scope: Full Account). **Никогда не коммитить в код** — иначе Vercel автоматически отзовёт токен. |

## 3. Связать Vercel-проект (если нужно)

1. https://vercel.com/dashboard
2. Проект для беты (prj_rSIA3SgwSDWTL0pfYVJTCiGVFAke)
3. Settings → Git — можно оставить отключённым, т.к. деплой идёт через CLI

## 4. Проверка

1. **Actions** → вкладка **Actions**
2. После push в `staging` запускается **Build and Deploy to Vercel (Demo/Beta)**
3. Если падает — смотрите логи, на каком шаге ошибка

## Миграции Supabase (checklists)

Если при создании чеклиста («задачи», «заготовка») появляется ошибка `Could not find the 'assigned_department' column` — примените миграции к staging Supabase:

```bash
cd restodocks_flutter && supabase db push
```

Или выполните миграцию вручную в SQL Editor Supabase: `supabase/migrations/20260304160000_ensure_assigned_department.sql`.

## Если Vercel отозвал токен

Vercel отзывает токены при обнаружении в публичном коде/логах. Создайте новый токен в Vercel → Account Settings → Tokens и обновите `VERCEL_TOKEN` в GitHub Secrets.

## Ручной запуск

Actions → **Build and Deploy to Vercel (Demo/Beta)** → **Run workflow** → **Run workflow**
