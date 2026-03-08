# Письмо при регистрации не приходит — что проверить

Если регистрация проходит, но письмо не приходит, после следующей регистрации появится оранжевое сообщение с текстом ошибки. Используйте его для диагностики.

## 1. Supabase: RESEND_API_KEY

1. Открой [Supabase Dashboard](https://supabase.com/dashboard)
2. Выбери проект (osglfptwbuqqmqunttha)
3. **Project Settings** (иконка шестерёнки слева внизу)
4. **Edge Functions** → **Secrets**
5. Проверь, есть ли `RESEND_API_KEY` (значение скрыто)
6. Если нет — **Add secret** → имя `RESEND_API_KEY`, значение — API-ключ из Resend (начинается с `re_`)

## 2. Resend: API-ключ и домен

1. Зайди в [Resend Dashboard](https://resend.com)
2. **API Keys** — создай ключ, скопируй и вставь в Supabase (шаг 1)
3. **Domains** — для продакшена добавь свой домен (например restodocks.com), настрой DNS
4. Без своего домена Resend отправляет с `onboarding@resend.dev` — только на email твоего аккаунта Resend и ограниченное число писем

## 3. Supabase: логи Edge Function

1. Supabase Dashboard → **Edge Functions**
2. Открой `send-registration-email`
3. Вкладка **Logs** — смотри ошибки при последней регистрации
4. Типичные ошибки:
   - `RESEND_API_KEY not configured` → добавь ключ в Secrets
   - `domain not verified` → настрой домен в Resend или используй onboarding@resend.dev только для тестового email

## 4. Деплой функции

Убедись, что Edge Function задеплоена:

```bash
cd restodocks_flutter
npx supabase functions deploy send-registration-email --project-ref osglfptwbuqqmqunttha
```
