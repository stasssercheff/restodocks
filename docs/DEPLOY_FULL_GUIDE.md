# Restodocks: полная инструкция по настройке

Пошаговая настройка Prod, Beta и Admin с нуля.

---

## 1. Что есть в проекте

| Компонент | Что это | Где живёт |
|-----------|---------|-----------|
| **Prod** | Основное приложение (Flutter) | Cloudflare Pages, ветка `main` |
| **Beta** | То же приложение для тестов | Cloudflare Pages, ветка `staging` |
| **Admin** | Панель управления (заведения, промокоды) | Cloudflare Workers |

Один репозиторий. Одна база Supabase. Prod и Beta — два разных **проекта** Cloudflare Pages. Admin — один **Worker**.

---

## 2. Подготовка: Cloudflare и GitHub

### 2.1 Cloudflare

1. Зайти на [dash.cloudflare.com](https://dash.cloudflare.com)
2. Запомнить **Account ID** (Overview → в правой колонке)
3. **API Token**: My Profile → API Tokens → Create Token → шаблон **Edit Cloudflare Workers** → создать → скопировать токен

### 2.2 GitHub

1. Репозиторий → **Settings** → **Actions** → **General**
2. **Actions permissions** → **Allow all actions and reusable workflows** → Save
3. **Settings** → **Secrets and variables** → **Actions** → New repository secret

Добавить секреты:

| Name | Value |
|------|-------|
| `CLOUDFLARE_API_TOKEN` | токен из п. 2.1 |
| `CLOUDFLARE_ACCOUNT_ID` | Account ID из Cloudflare |
| `SUPABASE_URL` | `https://osglfptwbuqqmqunttha.supabase.co` |
| `SUPABASE_ANON_KEY` | anon key из Supabase → Settings → API |

---

## 3. Supabase

1. Проект **osglfptwbuqqmqunttha**
2. **Settings** → **API** → скопировать **anon public**
3. **Authentication** → **URL Configuration** → **Redirect URLs** — добавить:

```
https://restodocks.com
https://restodocks.com/
https://www.restodocks.com
https://www.restodocks.com/
https://restodocks.pages.dev
https://*.restodocks.pages.dev
```

**Save**

---

## 4. Cloudflare Pages: Prod (основной сайт)

### 4.1 Создать проект

1. **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. Выбрать репозиторий Restodocks
3. **Production branch**: `main`

### 4.2 Build settings

| Поле | Значение |
|------|----------|
| Framework preset | **None** |
| Build command | `bash cloudflare-build.sh` |
| Build output directory | `restodocks_flutter/build/web` |
| Root directory | *(оставить пустым)* |

### 4.3 Environment Variables

**Settings** → **Variables and Secrets** → **Add**

| Name | Value |
|------|-------|
| `SUPABASE_URL` | `https://osglfptwbuqqmqunttha.supabase.co` |
| `SUPABASE_ANON_KEY` | anon key из Supabase |

Для Production и Preview — одинаково.

### 4.4 Preview branches

**Settings** → **Builds & deployments** → **Preview branch control** → **None**

(Prod не должен собираться при push в staging.)

### 4.5 Имя проекта

Если проект назван не `restodocks` — в `.github/workflows/deploy-cloudflare-prod.yml` указано `--project-name=restodocks`. Либо переименовать проект в Cloudflare в `restodocks`, либо поменять в workflow.

### 4.6 Как обновляется Prod

- **Вариант А**: Cloudflare Pages сам собирает при push в `main` (если Git integration включён)
- **Вариант Б**: Только GitHub Action `deploy-cloudflare-prod.yml` — тогда в Prod отключить **Enable automatic production branch deployments**

URL Prod: `https://restodocks.pages.dev` или кастомный домен (например `restodocks.com`).

---

## 5. Cloudflare Pages: Beta (тестовый сайт)

### 5.1 Создать проект

1. **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. Тот же репозиторий Restodocks
3. **Production branch**: `staging` (не main!)

### 5.2 Build settings

| Поле | Значение |
|------|----------|
| Framework preset | **None** |
| Build command | `bash cloudflare-build.sh` |
| Build output directory | `restodocks_flutter/build/web` |
| Root directory | *(пусто)* |

### 5.3 Environment Variables

Те же `SUPABASE_URL` и `SUPABASE_ANON_KEY`, что у Prod.

### 5.4 Preview branches

**None**

URL Beta: `https://restodocks-XXXX.pages.dev` (или другой subdomain — смотри в проекте).

---

## 6. Admin (панель управления)

Admin — это **Cloudflare Worker**, не Pages. Отдельный проект Pages для него не создаётся.

### 6.1 Cloudflare Workers Builds (Git)

| Поле | Значение |
|------|----------|
| **Path** | *(пусто)* |
| **Build command** | `bash deploy-admin.sh` |
| **Deploy command** | `bash deploy-admin-deploy.sh` |

### 6.2 Первый деплой (локально)

```bash
cd admin
npm install
```

Создать `.dev.vars` (для локального preview) или сразу настроить секреты в Cloudflare:

```
NEXT_PUBLIC_SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...   # service_role из Supabase → API
ADMIN_PASSWORD=ваш_секретный_пароль
```

Запустить деплой:

```bash
npm run deploy
```

При первом запуске: `wrangler login` (откроется браузер). Wrangler создаст Worker `restodocks-admin`.

### 6.3 Секреты в Cloudflare (если не заданы)

**Workers & Pages** → **restodocks-admin** → **Settings** → **Variables and Secrets**

Добавить:
- `ADMIN_PASSWORD`
- `SUPABASE_SERVICE_ROLE_KEY`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

### 6.4 URL админки

**Workers & Pages** → **restodocks-admin** → вверху URL вида:

`https://restodocks-admin.<аккаунт>.workers.dev`

Вход: пароль из `ADMIN_PASSWORD`. Вкладки: **Заведения**, **Промокоды**.

### 6.5 Деплой через GitHub

При push в `main` с изменениями в `admin/` запускается workflow **Deploy Admin to Cloudflare Workers**. Нужны секреты в GitHub: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (уже добавлены в п. 2.2).

---

## 7. Связь с GitHub — кратко

| Что | Ветка | Когда деплоится |
|-----|-------|-----------------|
| Prod | `main` | push в `main` (Pages или Action) |
| Beta | `staging` | push в `staging` (Pages) |
| Admin | `main` | push в `main` при изменениях в `admin/` (Action) |

Репозиторий один. Подключать отдельные репозитории не нужно. Prod и Beta — два проекта Pages в одном аккаунте Cloudflare, оба смотрят на один и тот же Git-репо, но на разные ветки.

---

## 8. Контрольный список

- [ ] GitHub Actions включены, секреты заданы
- [ ] Supabase: Redirect URLs содержат все домены
- [ ] Prod: Build command `bash cloudflare-build.sh`, output `restodocks_flutter/build/web`, env SUPABASE_*
- [ ] Beta: то же самое, Production branch = `staging`
- [ ] Admin: `cd admin && npm run deploy`, секреты в Worker
- [ ] Вход на Prod/Beta работает (один и тот же логин)
- [ ] Админка открывается, вход по ADMIN_PASSWORD

---

## 9. Типичные проблемы

**Вход «неверный пароль»** — проверить SUPABASE_URL, SUPABASE_ANON_KEY и Redirect URLs в Supabase.

**Prod обновляется при push в staging** — у Prod поставить Preview branches = None, при необходимости отключить авто-деплой Prod.

**Админка 401** — проверить ADMIN_PASSWORD и переменные в Worker.

**Build падает** — Root directory пустой, Build command из корня репо, env заданы для Production и Preview.
