# Деплой Restodocks на Vercel

## 1. Подключить репозиторий

1. [vercel.com](https://vercel.com) → **Add New** → **Project**
2. Импортируйте GitHub‑репозиторий **restodocks** (или `restodocks_flutter`).
3. **Root Directory**: если репо — вся папка с Flutter‑проектом, оставьте пустым. Если репо — родительская папка, укажите `restodocks_flutter`.

## 2. Переменные окружения

**Project Settings** → **Environment Variables** добавьте:

| Key               | Value                    | Environments      |
|-------------------|--------------------------|-------------------|
| `SUPABASE_URL`    | `https://....supabase.co`| Production, Preview|
| `SUPABASE_ANON_KEY` | `eyJ...` (anon key)   | Production, Preview|

Обязательно отметьте **Production** и **Preview**, иначе сборка упадёт.

## 3. Сборка

Сборка идёт по `vercel.json`:

- **Build Command**: `bash vercel-build.sh`
- **Output Directory**: `build/web`
- **Install Command**: пропуск npm (используется Flutter)

Скрипт устанавливает Flutter (git clone stable), генерирует `config.json` из env и запускает `flutter build web --release`.

### 3.1. Деплой через GitHub Actions (рекомендуется при таймаутах)

Если сборка на Vercel падает по таймауту (10 мин на Hobby) или после «Downloading Web SDK...», используйте **GitHub Actions**: сборка выполняется в Actions (лимит ~6 ч), затем в Vercel отправляется только готовый артефакт (`vercel deploy --prebuilt`).

1. **Workflow**: `.github/workflows/deploy.yml` — при каждом `push` в `main` запускается сборка и деплой.

2. **Секреты в GitHub** — репозиторий → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Создайте по одному секрету:

   - **VERCEL_TOKEN** — уже сделали: [vercel.com/account/tokens](https://vercel.com/account/tokens) → Create Token.

   - **VERCEL_PROJECT_ID** — Vercel → ваш проект Restodocks → вкладка **Settings** → раздел **General** → прокрутите вниз до **Project ID** (строка вида `prj_…`). Скопируйте и вставьте как значение секрета с именем **VERCEL_PROJECT_ID**.

   - **VERCEL_ORG_ID** — это ID вашего аккаунта или команды:
     - Либо: в каталоге проекта в терминале выполните `npx vercel link`, выберите проект. Появится папка `.vercel`. Откройте файл `.vercel/project.json` — там поле **orgId**. Его значение → секрет **VERCEL_ORG_ID**.
     - Либо: [vercel.com/account](https://vercel.com/account) → **Settings** → **General** → внизу страницы **User ID** (или в настройках команды — **Team ID**). Это значение → секрет **VERCEL_ORG_ID**.

   - **SUPABASE_URL** и **SUPABASE_ANON_KEY** — те же значения, что уже в Vercel: Vercel → проект → **Settings** → **Environment Variables**. Там уже есть `SUPABASE_URL` и `SUPABASE_ANON_KEY`. Скопируйте каждое значение и создайте в GitHub два секрета с именами **SUPABASE_URL** и **SUPABASE_ANON_KEY** и этими же значениями.

3. **Опционально**: в Vercel → **Settings** → **Git** отключите **Automatically deploy** для ветки `main`, чтобы не запускать две сборки (Actions будет деплоить сам).

4. После `git push origin main` смотрите **Actions** вкладку в GitHub. Успешный run → деплой в Vercel production.

## 4. Ограничения

- Первая сборка дольше из‑за установки Flutter (~3–7 мин). При таймауте (10 мин на Hobby) — увеличьте таймаут в плане.
- SPA‑маршрутизация настроена через `rewrites` в `vercel.json`.

## 4.1. Если деплой падает с ошибкой

1. **Где смотреть**: Vercel → проект → **Deployments** → нужный деплой → **Building** / лог. Ошибка обычно в **красном блоке** в конце лога.

2. **По логу сборки** (`vercel-build.sh` пишет шаги):
   - `==> Env OK` — переменные заданы.
   - `==> Installing Flutter...` / `==> flutter build web...` — на каком шаге остановилось.
   - `ERROR: ...` — причина (clone, pub get, build, config.json).

3. **Типичные причины**:
   - **Таймаут** (10 мин на Hobby): сборка не успевает. Решение: **Settings** → **General** → **Build Command Timeout** (если есть в плане) или апгрейд плана.
   - **SUPABASE_URL / SUPABASE_ANON_KEY not set**: не заданы в **Environment Variables** для Production/Preview.
   - **404 при скачивании Flutter/SDK**: сетевая ошибка или проблема на стороне Flutter; попробовать **Redeploy**.
   - **`build/web/index.html` not found**: сборка завершилась, но артефакт не создан — смотреть строки выше в логе (`flutter build web` упал или прерван).

4. **Ручной Redeploy**: Deployments → **⋯** у деплоя → **Redeploy** (иногда помогает при временных сбоях).

## 5. Подключение своего домена (Custom Domain)

Всё настраивается в **Vercel Dashboard** — изменения в коде не нужны.

1. **Vercel** → ваш проект Restodocks → вкладка **Settings** → **Domains**.
2. Нажмите **Add** и введите ваш домен (например `restodocks.com` или `www.restodocks.com`).
3. Vercel покажет, какие DNS‑записи нужны.

### Вариант A: DNS у регистратора (Reg.ru, Timeweb, Cloudflare и т.д.)

**Корень домена** (`example.com`):

- Тип **A**, имя `@`, значение **76.76.21.21** (Vercel).

**Поддомен www** (`www.example.com`):

- Тип **CNAME**, имя `www`, значение **cname.vercel-dns.com**.

Точные значения лучше брать из **Domains** в Vercel — они могут обновляться.

### Вариант B: Vercel DNS

1. В **Domains** выберите домен → **Use Vercel DNS**.
2. Vercel покажет 4 **Nameservers** (например `ns1.vercel-dns.com` и т.п.).
3. У регистратора домена в настройках DNS замените NS на эти 4 значения и сохраните.

После смены NS управление DNS будет в Vercel, домен подтянется сам.

### SSL (HTTPS)

Vercel сам выпускает сертификат для вашего домена. После корректной настройки DNS включится HTTPS и редирект с HTTP. Проверка домена: **Domains** → **Verify**; при ошибках — подождать обновления DNS (до 24–48 ч).

## 6. После деплоя

Проверьте основной URL и превью. Если видите «Ошибка конфигурации» — проверьте переменные и что выбран окружение **Production** / **Preview**.
