# Деплой Restodocks на Netlify

> **На паузе.** Сейчас используется Cloudflare Pages (основное приложение) и Cloudflare Workers (Admin).  
> См. [CLOUDFLARE_PAGES_DEPLOY.md](CLOUDFLARE_PAGES_DEPLOY.md) и [CLOUDFLARE_ADMIN_DEPLOY.md](CLOUDFLARE_ADMIN_DEPLOY.md).

---

Инструкция по настройке 4 сайтов на Netlify (для справки).

---

## Схема

| Сайт | Репозиторий | Base directory | Ветка | Supabase |
|------|-------------|----------------|-------|----------|
| Restodocks (prod) | restodocks | restodocks_flutter | main | Production |
| Restodocks Demo | restodocks | restodocks_flutter | staging | Staging |
| Admin (prod) | restodocks | beta-admin | main | Production |
| Admin Demo | restodocks | beta-admin | main или staging | Staging |

> Для Admin Demo можно использовать ветку `main` — отличие только в env (Staging Supabase).

---

## 1. Подготовка

Убедитесь, что:
- Аккаунт Netlify есть и подключён к GitHub
- В Supabase есть 2 проекта: **Production** и **Staging** (демо)
- Знаете URL и ключи из Supabase → Project Settings → API

---

## 2. Создание сайта 1: Restodocks (prod)

1. Netlify → **Add new site** → **Import an existing project**
2. **Connect to Git provider** → GitHub → выберите репозиторий `restodocks`
3. **Branch to deploy:** `main`
4. **Base directory:** `restodocks_flutter`
5. **Build command:** (оставьте пустым — берётся из netlify.toml)
6. **Publish directory:** (оставьте пустым — берётся из netlify.toml)
7. **Environment variables** → **Add variables** → **Add single variable** (или bulk):

   | Key | Value | Scopes |
   |-----|-------|--------|
   | `SUPABASE_URL` | Production Project URL из Supabase | All |
   | `SUPABASE_ANON_KEY` | Production anon public из Supabase | All |

8. **Deploy site**

9. (Опционально) **Domain settings** → **Add custom domain** → `www.restodocks.com` и т.д.

---

## 3. Создание сайта 2: Restodocks Demo

1. Netlify → **Add new site** → **Import an existing project**
2. Выберите тот же репозиторий `restodocks`
3. **Branch to deploy:** `staging`
4. **Base directory:** `restodocks_flutter`
5. **Environment variables:**

   | Key | Value |
   |-----|-------|
   | `SUPABASE_URL` | **Staging** Project URL из Supabase |
   | `SUPABASE_ANON_KEY` | **Staging** anon public из Supabase |

6. **Deploy site**

7. Получите URL вида `random-name-123.netlify.app` или настройте поддомен `demo.restodocks.com`

---

## 4. Создание сайта 3: Admin (prod)

1. Netlify → **Add new site** → **Import an existing project**
2. Выберите репозиторий `restodocks`
3. **Branch to deploy:** `main`
4. **Base directory:** `beta-admin`
5. **Environment variables:**

   | Key | Value |
   |-----|-------|
   | `NEXT_PUBLIC_SUPABASE_URL` | Production Project URL |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Production anon public |
   | `SUPABASE_SERVICE_ROLE_KEY` | Production service_role (Project Settings → API) |
   | `ADMIN_PASSWORD` | Пароль входа в админку |

6. **Deploy site**

---

## 5. Создание сайта 4: Admin Demo

1. Netlify → **Add new site** → **Import an existing project**
2. Репозиторий `restodocks`
3. **Branch to deploy:** `staging`
4. **Base directory:** `beta-admin`
5. **Environment variables** — те же ключи, но значения от **Staging** Supabase:

   | Key | Value |
   |-----|-------|
   | `NEXT_PUBLIC_SUPABASE_URL` | Staging Project URL |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Staging anon public |
   | `SUPABASE_SERVICE_ROLE_KEY` | Staging service_role |
   | `ADMIN_PASSWORD` | Пароль для демо-админки |

6. **Deploy site**

---

## 6. Если «Page not found» (404)

**Важно:** Base directory должен быть **`restodocks_flutter`** (не `/`).

Если стоит `/`, Netlify не подхватывает netlify.toml и редиректы SPA.  

**Исправление:** Site settings → Build & deploy → Build settings → **Base directory** = `restodocks_flutter` → Save → **Trigger deploy**.

Скрипт сборки добавляет `_redirects` в `build/web`, чтобы все пути (`/login`, `/menu` и т.д.) отдавали `index.html`.

---

## 7. Проверка

| Сайт | Что проверить |
|------|----------------|
| Restodocks prod | Логин, загрузка данных из Production Supabase |
| Restodocks Demo | Логин, данные из Staging Supabase |
| Admin prod | Логин по ADMIN_PASSWORD, промокоды, заведения |
| Admin Demo | То же для Staging |

---

## 8. Автодеплой

По умолчанию Netlify включает **Continuous deployment**:
- Push в `main` → деплой Restodocks prod и Admin prod
- Push в `staging` → деплой Restodocks Demo и Admin Demo

Чтобы отключить автодеплой для конкретного сайта: Site settings → Build & deploy → Continuous deployment → **Stop builds**.

---

## 9. Контроль расходов

Netlify бесплатный тариф (Starter):
- 300 мин сборки в месяц
- 100 ГБ трафика
- Неограниченное количество сайтов

Flutter-сборка ~5–10 мин, Next.js ~2–3 мин. При 4 сайтах и редких пушах лимитов хватает.

---

## 10. Файлы в репозитории

- `restodocks_flutter/netlify.toml` — конфиг для Flutter
- `restodocks_flutter/netlify-build.sh` — скрипт сборки Flutter
- `beta-admin/netlify.toml` — конфиг для Next.js Admin

Главное изменение в коде: `main.dart` читает `SUPABASE_URL` и `SUPABASE_ANON_KEY` через `--dart-define` (при сборке подставляются из Netlify env).

---

## 11. Vercel vs Netlify — один и тот же код

Да, всё, что сейчас задеплоено на Vercel, можно выложить и на Netlify. Исходники одни и те же, отличаются только:

- **Сборка:** Netlify сам ставит Flutter и запускает `netlify-build.sh`; Vercel использует GitHub Actions + Vercel CLI.
- **Env:** В Netlify задаются `SUPABASE_URL` и `SUPABASE_ANON_KEY` в Site settings.
- **Ветки:** Prod — `main`, Demo — `staging`.

После правок достаточно push в нужную ветку, и Netlify сделает новый деплой с тем же кодом.

---

## 12. DeepL и нейросети — не в Netlify/Vercel

**DeepL** и AI (GigaChat, Gemini, OpenAI) подключены к **Supabase Edge Functions**, а не к Vercel или Netlify.

| Что | Где настроено |
|-----|----------------|
| DeepL | Supabase → Edge Functions → Secrets → `DEEPL_API_KEY` |
| translate-text | Edge Function, вызывает DeepL для переводов ТТК, продуктов, заказов |
| auto-translate-product | Edge Function, переводит продукты пачками через DeepL |
| GigaChat / Gemini / OpenAI | Supabase Secrets: `GIGACHAT_AUTH_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY` |

Приложение вызывает Supabase (`SUPABASE_URL` + `SUPABASE_ANON_KEY`). Edge Functions лежат в Supabase и используют свои секреты. При деплое на Netlify DeepL и AI продолжают работать — достаточно тех же `SUPABASE_URL` и `SUPABASE_ANON_KEY`. Менять конфигурацию не нужно.
