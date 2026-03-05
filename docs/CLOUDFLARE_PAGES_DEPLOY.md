# Деплой Restodocks на Cloudflare Pages

Основной хостинг. Netlify выключен, миграция завершена.  
Инструкция с учётом лимитов (500 сборок/месяц бесплатно).

---

## Лимиты Cloudflare Pages (Free)

| Параметр | Значение |
|----------|----------|
| Сборок в месяц | 500 |
| Одновременных сборок | 1 |
| Бандид | безлимит |
| Проектов | до 100 |

**Экономия сборок:** отключите «Builds for non-production branches» и используйте Build watch paths (см. раздел 9).

---

## Схема

| Сайт | Root directory | Production branch | Supabase |
|------|----------------|-------------------|----------|
| Restodocks (prod) | restodocks_flutter | main | Production |
| Restodocks Demo | restodocks_flutter | staging | Staging |
| Admin (prod) | beta-admin | main | Production |
| Admin Demo | beta-admin | staging | Staging |

> **Admin** (Next.js с SSR): на Cloudflare нужен @cloudflare/next-on-pages — отдельная настройка. Restodocks (Flutter) — готов.

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

## 7. Экономия сборок (не выйти за 500/месяц)

В **Settings → Builds & deployments** каждого проекта:

1. **Builds for non-production branches: Disabled** — не собирать каждый PR и feature branch.
2. **Build watch paths** (если доступно) — включить только нужные папки:
   - Restodocks: `restodocks_flutter/**` — сборка только при изменении Flutter.
3. Пушить осознанно: 1 push в main ≈ 1 сборка Restodocks prod; 1 push в staging ≈ 1 сборка Demo.  
   При ~10–20 пушах в неделю в main и staging укладываемся в 500/месяц.

---

## 8. Файлы в репозитории

- `restodocks_flutter/cloudflare-build.sh` — скрипт сборки для Cloudflare Pages
- Генерирует `_redirects` (SPA-маршрутизация) и `_headers` (кэш) в `build/web`

---

## 9. DeepL и нейросети

Подключены к **Supabase Edge Functions**, не к Cloudflare. При переходе на Pages меняется только хостинг Flutter-приложения — Supabase, Edge Functions и секреты остаются без изменений.

---

## 10. Чек-лист миграции

| Шаг | Действие | Статус |
|-----|----------|--------|
| 1 | Restodocks Demo (staging) на Cloudflare Pages | ✓ задеплоено |
| 2 | Restodocks prod (main) — создать 2-й проект Pages, main, Production Supabase | |
| 3 | В обоих: Builds for non-production branches = Disabled | |
| 4 | Admin prod + Admin Demo — Cloudflare (next-on-pages) или Vercel | |
| 5 | Перенести домены на Cloudflare (когда всё проверено) | |
