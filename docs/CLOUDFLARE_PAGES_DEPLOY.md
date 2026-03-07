# Деплой Restodocks на Cloudflare Pages

При каждом переносе на новый хостинг (Vercel → Netlify → Cloudflare) нужно правильно настроить **одну и ту же базу Supabase** и **добавить домен в Supabase Auth**. Без этого вход срывается с «неверный пароль».

---

## Что обязательно сделать

### 1. Environment Variables в Cloudflare Pages

Cloudflare Pages → проект → **Settings** → **Variables and Secrets**

**Одна БД** — Prod и Beta используют один Supabase. Задайте одинаковые значения:

| Проект | SUPABASE_URL | SUPABASE_ANON_KEY |
|--------|--------------|-------------------|
| Prod | `https://osglfptwbuqqmqunttha.supabase.co` | anon key из Supabase (Dashboard → API) |
| Beta | `https://osglfptwbuqqmqunttha.supabase.co` | тот же anon key |

Prod и Beta используют **один** проект Supabase (osglfptwbuqqmqunttha).

**Чек-лист: вход на Prod не работает, Beta работает**
1. Cloudflare Prod → Build command: `bash cloudflare-build.sh` (как у Beta)
2. Root directory: пусто (оба одинаково)
3. Preview branch = None в обоих
4. SUPABASE_URL и SUPABASE_ANON_KEY — одинаковые в Prod и Beta
5. Retry deployment Prod с Clear build cache

**Если всё равно не работает** — см. [CLOUDFLARE_LOGIN_FIX.md](CLOUDFLARE_LOGIN_FIX.md).

**Admin** — см. [CLOUDFLARE_ADMIN_DEPLOY.md](CLOUDFLARE_ADMIN_DEPLOY.md).

### 2. Supabase Auth: Redirect URLs

Supabase → проект osglfptwbuqqmqunttha → **Authentication** → **URL Configuration** → **Redirect URLs**. Добавьте:

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

**Критично:** Production branch разный — иначе оба сайта обновляются вместе.

| Параметр | Prod | Beta |
|----------|------|------|
| Production branch | **main** (только!) | **staging** (только!) |
| Root directory | **пусто** (корень репо) | **пусто** |
| Build command | `bash cloudflare-build.sh` | `bash cloudflare-build.sh` |
| Build output | `restodocks_flutter/build/web` | `restodocks_flutter/build/web` |
| Env | SUPABASE_URL, SUPABASE_ANON_KEY (одни и те же) | те же |
| Preview branch | **None** (обязательно!) | **None** (обязательно!) |

Если Preview включён — будут строиться ветки при push, и Prod может обновиться от staging.

**Prod обновляется при push в staging — Cloudflare не должен вообще запускать Prod-сборку.**  
Prod → Settings → Builds & deployments → **Preview branch control** = **None**.  
При None Cloudflare не строит preview-ветки — staging для Prod считается preview (production = main), поэтому сборка не запустится. Если стоит "All non-Production branches" — смени на **None**.

**Если Preview=None уже стоит, а Prod всё равно строит при push в staging** — см. раздел «Prod: только GitHub Action» ниже.

**Если вход на Prod не работает** — убедись, что Prod использует ТОЧНО такой же Build command и Root directory, как Beta. Оба должны вызывать `bash cloudflare-build.sh` из корня.

- **Framework preset**: None

### 4. Деплой каждые 5 минут

Если деплои идут без пуша — Cloudflare → проект → **Settings** → **Builds & deployments**. Проверить: **Retry policy** (отключить автоповтор), лишние **Build hooks**. Должен быть деплой только по push.

### 5. Пересборка после правок env

После добавления/изменения Environment Variables нужно **Clear build cache** и **Retry deployment**, чтобы сборка использовала новые значения.

---

### Prod: только GitHub Action (Cloudflare не запускает Prod при push в staging)

Если Prod всё равно собирается при push в staging, несмотря на Preview=None:

1. **Отключить авто-деплой Prod по Git.**  
   Prod → Settings → Builds & deployments → **Configure Production deployments** → снять галочку **Enable automatic production branch deployments** → Save.

2. **Деплой Prod только через GitHub Action.**  
   Workflow `deploy-cloudflare-prod.yml` запускается **только при push в main**. Сборка и деплой — в GitHub, Cloudflare не получает webhook'и для Prod (или получает, но не деплоит).

3. **Секреты в GitHub:**  
   Settings → Secrets → Actions → добавить:
   - `CLOUDFLARE_API_TOKEN` — Cloudflare API Token (Account → Cloudflare Pages → Edit)
   - `CLOUDFLARE_ACCOUNT_ID` — ID аккаунта (в правой колонке Overview)

4. **Имя проекта.**  
   В workflow `--project-name=restodocks`. Если проект называется иначе — изменить в `.github/workflows/deploy-cloudflare-prod.yml`.

Итог: Prod обновляется **только** при push в main, через Action. Push в staging — Cloudflare Prod вообще не трогает.

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
