# Настройка Send Email Hook (письма подтверждения через Resend)

Если письмо с ссылкой подтверждения не приходит через SMTP, используй Auth Hook — Supabase будет вызывать нашу Edge Function, которая шлёт через Resend.

## 1. Deploy функции

```bash
cd restodocks_flutter
npx supabase functions deploy auth-send-email --project-ref osglfptwbuqqmqunttha
```

## 2. Секреты

Функция уже использует `RESEND_API_KEY`. Добавь `SEND_EMAIL_HOOK_SECRET`:

1. Supabase Dashboard → **Authentication** → **Hooks**
2. **Send Email** hook → **Create** (если нет)
3. Нажми **Generate Secret** — скопируй значение (формат `v1,whsec_...`)
4. Supabase Dashboard → **Project Settings** → **Edge Functions** → **Secrets**
5. Add: `SEND_EMAIL_HOOK_SECRET` = скопированное значение

Или через CLI:
```bash
npx supabase secrets set SEND_EMAIL_HOOK_SECRET="v1,whsec_ТВОЙ_СЕКРЕТ" --project-ref osglfptwbuqqmqunttha
```

## 3. Подключить hook к функции

1. **Authentication** → **Hooks** → **Send Email**
2. **URL**: `https://osglfptwbuqqmqunttha.supabase.co/functions/v1/auth-send-email`
3. **Create** / **Save**

После этого Supabase будет вызывать `auth-send-email` вместо SMTP. Письма пойдут через Resend (как заказы и регистрационные данные).

## Если письмо не приходит

1. **Edge Functions → auth-send-email → Logs** — смотри, вызывалась ли функция при регистрации.
   - Если логов нет — hook не срабатывает (проверь, что он включён и URL верный).
   - Если есть `auth-send-email ERROR: ...signature...` — `SEND_EMAIL_HOOK_SECRET` в Secrets должен совпадать с секретом в Auth Hooks.
   - Если есть `Resend error` — смотри ошибку Resend.

2. **Authentication → Logs** — смотри, есть ли ошибки при signup.
