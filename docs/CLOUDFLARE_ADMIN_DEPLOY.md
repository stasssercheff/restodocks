# Деплой Admin на Cloudflare Workers

Admin — Next.js приложение. Деплоится на Cloudflare Workers через @opennextjs/cloudflare.

---

## Cloudflare Workers Builds (Git)

Если подключаешь Worker к Git в Cloudflare Dashboard:

| Поле | Значение |
|------|----------|
| **Path** (Root directory) | `admin` |
| **Build command** | `bash build.sh` |
| **Deploy command** | `bash deploy.sh` |

Скрипты `admin/build.sh` и `admin/deploy.sh` — Path=admin, команды из папки admin.

---

## Где админка

После деплоя админка доступна по URL Cloudflare Workers:

- **Cloudflare Dashboard** → **Workers & Pages** → **restodocks-admin** → вверху показан URL вида:
  - `https://restodocks-admin.<ваш-аккаунт>.workers.dev`
- Либо можно добавить кастомный домен (например `admin.restodocks.com`) в настройках Worker → **Triggers** → **Custom Domains**

Вход: пароль из `ADMIN_PASSWORD`. Вкладки: **Заведения**, **Промокоды**.

---

## 1. Подготовка

1. Cloudflare аккаунт, Wrangler CLI
2. В терминале: `cd admin`

---

## 2. Установка зависимостей

```bash
cd admin
npm install
```

---

## 3. Переменные окружения

Скопируйте `.dev.vars.example` → `.dev.vars` и заполните (или используйте `.env.local`):

```
NEXT_PUBLIC_SUPABASE_URL=https://osglfptwbuqqmqunttha.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
ADMIN_PASSWORD=ваш_пароль
```

Для **продакшена** задайте секреты в Cloudflare:

```bash
npx wrangler secret put ADMIN_PASSWORD
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
npx wrangler secret put NEXT_PUBLIC_SUPABASE_URL
npx wrangler secret put NEXT_PUBLIC_SUPABASE_ANON_KEY
```

Либо через Cloudflare Dashboard → Workers & Pages → ваш Worker → Settings → Variables and Secrets.

---

## 4. Сборка и деплой

```bash
npm run deploy
```

Первая команда запросит логин в Cloudflare (если ещё не выполнен `wrangler login`).

---

## 5. Локальный preview

```bash
npm run preview
```

---

## 6. Одна БД

Prod и Admin Demo используют один Supabase (osglfptwbuqqmqunttha).

## 7. GitHub Actions

Деплой админки — **только вручную**: GitHub → Actions → Deploy Admin to Cloudflare Workers → Run workflow. Автодеплой отключён, чтобы не тратить лимиты.
