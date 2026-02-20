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

## 3. Миграция базы данных

Выполните миграцию для таблицы токенов сброса пароля:

**Supabase** → **SQL Editor** → вставьте и выполните содержимое файла:

```
restodocks_flutter/supabase/migrations/20260220000001_password_reset_tokens.sql
```

## 4. Деплой Edge Functions

```bash
cd restodocks_flutter

# Деплой всех функций
npx supabase functions deploy send-email
npx supabase functions deploy send-registration-email
npx supabase functions deploy request-password-reset
npx supabase functions deploy reset-password

# Обновить ai-generate-checklist
npx supabase functions deploy ai-generate-checklist
```

## 5. AI чеклист — предпочтение Gemini

Если GigaChat недоступен из региона Supabase (EarlyDrop в логах), установите в секретах:

| Имя | Значение |
|-----|----------|
| `AI_PROVIDER` | `gemini` |

При наличии `GEMINI_API_KEY` функция будет использовать Gemini (обычно быстрее из ap-northeast-1).
