# Деплой Restodocks на Cloudflare Pages

При каждом переносе на новый хостинг (Vercel → Netlify → Cloudflare) нужно правильно настроить **одну и ту же базу Supabase** и **добавить домен в Supabase Auth**. Без этого вход срывается с «неверный пароль».

---

## Что обязательно сделать

### 1. Environment Variables в Cloudflare Pages

Cloudflare Pages → проект → **Settings** → **Variables and Secrets**

**Одна БД** — Prod и Beta используют один Supabase. Задайте одинаковые значения:

| Проект | SUPABASE_URL | SUPABASE_ANON_KEY |
|--------|--------------|-------------------|
| Prod | `https://kzhaezanjttvnqkgpxnh.supabase.co` | anon key из Supabase (Dashboard → API) |
| Beta | `https://kzhaezanjttvnqkgpxnh.supabase.co` | тот же anon key |

Скопируй из Beta в Prod — один проект Supabase для обоих.

> После переключения Prod на эту БД можно **остановить** второй проект Supabase (osglfptwbuqqmqunttha), чтобы не платить за два.

**Чек-лист: вход на Prod не работает, Beta работает**
1. Cloudflare Prod → Build command: `bash cloudflare-build.sh` (как у Beta)
2. Root directory: пусто (оба одинаково)
3. Preview branch = None в обоих
4. SUPABASE_URL и SUPABASE_ANON_KEY — одинаковые в Prod и Beta
5. Retry deployment Prod с Clear build cache

**Если всё равно не работает** — см. [CLOUDFLARE_LOGIN_FIX.md](CLOUDFLARE_LOGIN_FIX.md).

**Admin** — см. [CLOUDFLARE_ADMIN_DEPLOY.md](CLOUDFLARE_ADMIN_DEPLOY.md).

### 2. Supabase Auth: Redirect URLs

Supabase → проект (тот что kzhaezanjttvnqkgpxnh) → **Authentication** → **URL Configuration** → **Redirect URLs**. Добавьте:

```
https://restodocks.com
https://restodocks.com/
https://www.restodocks.com
https://www.restodocks.com/
https://restodocks.pages.dev
https://*.restodocks.pages.dev
```

**Save**

### 3. Сборка Cloudflare Pages

**Prod и Beta — ИДЕНТИЧНАЯ конфигурация** (иначе вход на Prod ломается):

| Параметр | Prod | Beta |
|----------|------|------|
| Production branch | `main` | `staging` |
| Root directory | **пусто** (корень репо) | **пусто** |
| Build command | `bash cloudflare-build.sh` | `bash cloudflare-build.sh` |
| Build output | `restodocks_flutter/build/web` | `restodocks_flutter/build/web` |
| Env | SUPABASE_URL, SUPABASE_ANON_KEY (одни и те же) | те же |
| Preview branch | None | None |

**Если вход на Prod не работает** — убедись, что Prod использует ТОЧНО такой же Build command и Root directory, как Beta. Оба должны вызывать `bash cloudflare-build.sh` из корня.

- **Framework preset**: None

### 4. Деплой каждые 5 минут

Если деплои идут без пуша — Cloudflare → проект → **Settings** → **Builds & deployments**. Проверить: **Retry policy** (отключить автоповтор), лишние **Build hooks**. Должен быть деплой только по push.

### 5. Пересборка после правок env

После добавления/изменения Environment Variables нужно **Clear build cache** и **Retry deployment**, чтобы сборка использовала новые значения.

---

## Настройка кастомного домена (Namecheap)

DNS остаётся в Namecheap (Resend, почта и др. — не трогать). Записи добавляем вручную.

### Шаг 1: Добавить домен в Cloudflare Pages

1. Cloudflare Dashboard → **Workers & Pages** → проект Restodocks → **Custom domains**
2. **Set up a custom domain** → введите `www.restodocks.com` → **Continue**
3. Cloudflare создаст запись. Пока домен не привязан — будет 522, это нормально.
4. При необходимости добавьте и `restodocks.com` (apex) — см. шаг 3.

> Важно: домен нужно сначала привязать в Pages, иначе CNAME даст 522.

### Шаг 2: CNAME для www

Namecheap → Domain List → ваш домен → **Manage** → **Advanced DNS**:

| Type | Host | Value | TTL |
|------|------|-------|-----|
| CNAME | www | `restodocks.pages.dev` | Automatic |

(У prod-проекта URL может быть другим — смотрите в Custom domains.)

### Шаг 3: Apex (restodocks.com без www)

DNS не позволяет CNAME на apex. Варианты:

**А) URL Redirect в Namecheap** (простой):  
Domain List → Manage → **Redirect Domain** → redirect `restodocks.com` → `https://www.restodocks.com`

**Б) A-записи Cloudflare** (если apex добавлен в Pages):  
Cloudflare покажет IP в Custom domains. Добавьте в Namecheap:

| Type | Host | Value |
|------|------|-------|
| A | @ | `188.114.96.1` |
| A | @ | `188.114.97.1` |
| AAAA | @ | `2a06:98c1:3600::1` |
| AAAA | @ | `2a06:98c1:3601::1` |

> Точные IP смотрите в Cloudflare Pages → Custom domains при добавлении apex.

### Шаг 4: Supabase Auth

В Supabase → **Authentication** → **URL Configuration** → **Redirect URLs** добавьте:

```
https://www.restodocks.com
https://www.restodocks.com/
https://restodocks.com
https://restodocks.com/
```

### Итого

- Не трогать: MX, TXT (Resend, почта), прочие записи
- Добавить: CNAME `www` → `restodocks.pages.dev`
- Apex: Redirect или A/AAAA по инструкции выше

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
