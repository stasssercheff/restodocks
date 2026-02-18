# Исправление подключения Vercel к GitHub

## Проблема:
"No Active Branches" и "Commit using our Git connections" означает, что Vercel потерял подключение к GitHub репозиторию.

## Решение:

### Шаг 1: Проверить репозиторий на GitHub
1. Перейдите на https://github.com/stasssercheff/restodocks
2. Убедитесь, что репозиторий существует и доступен
3. Проверьте последние коммиты - они должны быть

### Шаг 2: Переподключить Vercel
1. Зайдите в Vercel Dashboard: https://vercel.com/dashboard
2. Найдите проект "restodocks"
3. Если проект есть:
   - Перейдите в Settings → Git
   - Проверьте подключение к GitHub
   - Если подключение сломано - удалите и создайте заново

### Шаг 3: Если проекта нет - создать новый
1. Нажмите "Add New..." → "Project"
2. Выберите "Import Git Repository"
3. Найдите и выберите `stasssercheff/restodocks`
4. Настройте параметры сборки:
   ```
   Framework: Other
   Root Directory: restodocks_flutter
   Build Command: bash vercel-build.sh
   Output Directory: build/web
   Install Command: echo 'Flutter build — skip npm install'
   ```
5. Добавьте Environment Variables:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SKIP_FLUTTER_BUILD=true`

### Шаг 4: Проверить Webhook на GitHub
1. В GitHub репозитории: Settings → Webhooks
2. Должен быть webhook от Vercel
3. Если нет - Vercel создаст его автоматически при переподключении

### Шаг 5: Тестовый деплой
1. После настройки - Vercel должен автоматически запустить сборку
2. Или нажмите "Deploy" вручную
3. Статус должен измениться с "No Active Branches" на "Building"

## После исправления:
- Все новые коммиты будут автоматически деплоиться
- Статус проекта станет активным
- Push'и будут доходить до Vercel