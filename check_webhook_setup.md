# Проверка настройки Webhook Vercel ↔ GitHub

## Текущие настройки (что показывает пользователь):
- ✅ Pull Request Comments
- ✅ Commit Comments
- ✅ deployment_status Events
- ✅ repository_dispatch Events

## Что должно быть включено для деплоя:

### Обязательно:
- ✅ **Push events** (обычно включены по умолчанию)
- ✅ **Pull requests** (для PR комментариев)

### Рекомендуется:
- ✅ **deployment_status Events** (уже включено)
- ✅ **repository_dispatch Events** (уже включено)

## Проверка webhook:

### В GitHub:
1. Репозиторий → Settings → Webhooks
2. Должен быть webhook с URL: `https://vercel.com/api/webhooks/...`
3. Статус: ✅ **Active** (зеленая галочка)

### Если webhook отсутствует:
- Vercel не подключен к репозиторию
- Нужно переподключить проект в Vercel

### Если webhook есть, но не работает:
1. Нажмите "Edit" на webhook
2. В разделе "Which events would you like to trigger this webhook?"
3. Убедитесь, что выбрано "Send me everything" ИЛИ минимум:
   - ✅ Push
   - ✅ Pull requests
   - ✅ Deployment statuses

## Решение:
Если webhook отсутствует или неактивен - **переподключите Vercel проект** к GitHub репозиторию.