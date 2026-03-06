# Деплой Admin на Cloudflare Workers

Admin (beta-admin) — Next.js приложение. Деплоится на Cloudflare Workers через @opennextjs/cloudflare.

---

## 1. Подготовка

1. Cloudflare аккаунт, Wrangler CLI
2. В терминале: `cd beta-admin`

---

## 2. Установка зависимостей

```bash
cd beta-admin
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

## 6. Production vs Staging

Для **Admin Prod** используйте Production Supabase (osglfptwbuqqmqunttha).  
Для **Admin Demo** — Staging (kzhaezanjttvnqkgpxnh). Создайте два Workers с разными именами и разными env.
