# Деплой Restodocks на Cloudflare Pages

Инструкция по настройке Restodocks Flutter на Cloudflare Pages (prod и demo).

---

## Схема

| Сайт | Репозиторий | Root directory | Production branch | Supabase |
|------|-------------|----------------|-------------------|----------|
| Restodocks (prod) | restodocks | restodocks_flutter | main | Production |
| Restodocks Demo | restodocks | restodocks_flutter | staging | Staging |

---

## 1. Подготовка

- Аккаунт Cloudflare
- Репозиторий на GitHub
- Supabase: Production и Staging проекты, URL и anon key из Project Settings → API

---

## 2. Создание проекта Restodocks (prod)

1. [Cloudflare Dashboard](https://dash.cloudflare.com/) → **Workers & Pages** → **Create application** → **Pages** → **Connect to Git**
2. Авторизуйте GitHub, выберите репозиторий `restodocks`
3. **Set up builds and deployments**:
   - **Production branch:** `main`
   - **Root directory (advanced):** `restodocks_flutter`
   - **Build command:** `chmod +x cloudflare-build.sh && ./cloudflare-build.sh`
   - **Build output directory:** `build/web`
4. **Environment variables** → **Add variable**:
   | Key | Value | Environment |
   |-----|-------|-------------|
   | `SUPABASE_URL` | Production Project URL из Supabase | Production, Preview |
   | `SUPABASE_ANON_KEY` | Production anon public из Supabase | Production, Preview |
5. **Save and Deploy**

---

## 3. Создание проекта Restodocks Demo

1. **Create application** → **Pages** → **Connect to Git**
2. Тот же репозиторий `restodocks`
3. **Set up builds**:
   - **Production branch:** `staging`
   - **Root directory:** `restodocks_flutter`
   - **Build command:** `chmod +x cloudflare-build.sh && ./cloudflare-build.sh`
   - **Build output directory:** `build/web`
4. **Environment variables** — те же ключи, значения от **Staging** Supabase
5. **Save and Deploy**

---

## 4. Кастомный домен (опционально)

Pages → ваш проект → **Custom domains** → **Set up a custom domain**:
- prod: `www.restodocks.com` или `restodocks.com`
- demo: `demo.restodocks.com`

---

## 5. Если «Page not found» (404)

Убедитесь, что:
- **Root directory** = `restodocks_flutter` (не `/`)
- В `build/web` попадает файл `_redirects` с `/* /index.html 200` (его создаёт `cloudflare-build.sh`)

При проблемах: Project → **Settings** → **Builds & deployments** → **Retry deployment**.

---

## 6. Автодеплой

- Push в `main` → деплой Restodocks prod
- Push в `staging` → деплой Restodocks Demo  
Preview-деплои создаются для веток и pull requests.

---

## 7. Файлы в репозитории

- `restodocks_flutter/cloudflare-build.sh` — скрипт сборки для Cloudflare Pages
- Генерирует `_redirects` (SPA-маршрутизация) и `_headers` (кэш) в `build/web`

---

## 8. DeepL и нейросети

Подключены к **Supabase Edge Functions**, не к Cloudflare. При переходе на Pages меняется только хостинг Flutter-приложения — Supabase, Edge Functions и секреты остаются без изменений.
