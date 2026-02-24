# Настройка Resend и email-рассылки

## 1. Секреты в Supabase

В **Supabase Dashboard** → **Project Settings** → **Edge Functions** → **Secrets** добавьте:

| Имя | Значение |
|-----|----------|
| `RESEND_API_KEY` | Ваш API-ключ Resend (начинается с `re_`) |
| `RESEND_FROM_EMAIL` | (опционально) От кого письма, например `Restodocks <noreply@ваш-домен.com>`. По умолчанию используется `onboarding@resend.dev` для тестов |
| `APP_URL` | (для сброса пароля) URL приложения, например `https://restodocks.vercel.app` |

## 2. Домен для писем

По умолчанию Resend отправляет с `onboarding@resend.dev` — это работает только для тестов (ограниченное число писем).

Для продакшена:
1. Зайдите в [Resend Dashboard](https://resend.com/domains)
2. Добавьте свой домен
3. Настройте DNS-записи
4. Укажите в секретах: `RESEND_FROM_EMAIL` = `Restodocks <noreply@ваш-домен.com>`

## 3. Письмо после подтверждения email

При подтверждении email пользователем (клик по ссылке из Supabase) автоматически отправляется письмо «Регистрация подтверждена».

**Настройка (один раз):** добавьте anon key в Vault, чтобы триггер мог вызывать Edge Function:

**Supabase** → **SQL Editor**:
```sql
SELECT vault.create_secret(
  'ВАШ_ANON_KEY',  -- из Project Settings → API
  'supabase_anon_key',
  'Edge Function auth from triggers'
);
```

**Миграция:** `supabase/migrations/20260223200000_send_email_on_email_confirmed.sql`

## 4. Миграция базы данных

Выполните миграцию для таблицы токенов сброса пароля:

**Supabase** → **SQL Editor** → вставьте и выполните содержимое файла:

```
restodocks_flutter/supabase/migrations/20260220000001_password_reset_tokens.sql
```

## 5. Деплой Edge Functions

**Автоматически:** при push в `main` с изменениями в `restodocks_flutter/supabase/functions/` GitHub Action деплоит все функции. Добавьте секрет: GitHub → Settings → Secrets → New repository secret, имя `SUPABASE_ACCESS_TOKEN`, значение — токен из https://supabase.com/dashboard/account/tokens

**Вручную** (из корня репо):
```bash
npx supabase functions deploy --project-ref osglfptwbuqqmqunttha
```

## 6. AI чеклист — предпочтение Gemini

Если GigaChat недоступен из региона Supabase (EarlyDrop в логах), установите в секретах:

| Имя | Значение |
|-----|----------|
| `AI_PROVIDER` | `gemini` |

При наличии `GEMINI_API_KEY` функция будет использовать Gemini (обычно быстрее из ap-northeast-1).
