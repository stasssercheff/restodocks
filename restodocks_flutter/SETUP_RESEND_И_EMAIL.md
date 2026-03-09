# Настройка Resend и email-рассылки

## 1. Секреты в Supabase

В **Supabase Dashboard** → **Project Settings** → **Edge Functions** → **Secrets** добавьте:

| Имя | Значение |
|-----|----------|
| `RESEND_API_KEY` | Ваш API-ключ Resend (начинается с `re_`) |
| `RESEND_FROM_EMAIL` | (опционально) От кого письма, например `Restodocks <noreply@ваш-домен.com>`. По умолчанию используется `onboarding@resend.dev` для тестов |
| `APP_URL` | (для сброса пароля) URL приложения, например `https://restodocks.vercel.app` |

## 2. Домен для писем

По умолчанию Resend отправляет с `onboarding@resend.dev` — это работает только для тестов (ограниченное число писем). **Письма с onboarding@resend.dev часто попадают в спам.**

Для продакшена:
1. Зайдите в [Resend Dashboard](https://resend.com/domains)
2. Добавьте свой домен (например `restodocks.com`)
3. Настройте DNS-записи (см. раздел «Письма в спам» ниже)
4. Укажите в секретах: `RESEND_FROM_EMAIL` = `Restodocks <noreply@restodocks.com>`

---

## Письма попадают в спам — что делать

Чтобы письма не попадали в спам, нужна проверка домена и корректные DNS-записи.

### 1. Добавь домен в Resend

1. [Resend Dashboard](https://resend.com/domains) → **Add Domain**
2. Введи домен (например `restodocks.com`)

### 2. Добавь DNS-записи у хостинга домена (Cloudflare, регистратор и т.п.)

Resend покажет точные значения. Обычно нужны:

| Тип | Имя хоста | Значение |
|-----|-----------|----------|
| **MX** | `send` (или `em1234.restodocks.com`) | Указанный Resend |
| **TXT (SPF)** | `send` | `v=spf1 include:amazonses.com ~all` |
| **TXT (DKIM)** | `resend._domainkey` | Длинный ключ из Resend |

**Важно:** Создай поддомен `send.restodocks.com` для отправки — Resend использует его как return-path. Или используй точные имена из Resend Dashboard.

### 3. DMARC (рекомендуется)

Создай TXT-запись:

| Имя хоста | Значение |
|-----------|----------|
| `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@restodocks.com` |

После проверки можно усилить: `p=quarantine` или `p=reject`.

### 4. Cloudflare

- **DNS-запись MX:** Proxy (оранжевое облако) — **выключен** (серый)
- **TXT-записи:** Proxy не используется
- [Resend + Cloudflare](https://resend.com/docs/knowledge-base/cloudflare) — возможен Domain Connect для быстрой настройки

### 5. Проверка в Resend

После добавления DNS подожди 5–15 минут (иногда до 48 часов) и нажми **Verify** в Resend. Статус должен стать «Verified».

### 6. Дополнительно

- **От кого:** Используй `Restodocks <noreply@restodocks.com>`, а не общий адрес вроде `info@` или `mail@`
- **Тема и текст:** Избегай спам-слов («Бесплатно», «Срочно», «Выигрыш», избыток восклицаний)
- **Транзакционные письма:** Регистрация, сброс пароля и т.п. обычно лучше проходят, чем рассылки

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

**Автоматически:** при push в `main` с изменениями в `restodocks_flutter/supabase/functions/` или `restodocks_flutter/supabase/config.toml` GitHub Action деплоит все функции.

> **Важно:** Функция `send-email` настроена с `verify_jwt = false` в config.toml, т.к. сотрудники входят через legacy authenticate-employee без Supabase Auth JWT. Без этого отправка заказа по почте даёт 403 Forbidden. После изменения config.toml нужен повторный деплой.

Добавьте секрет: GitHub → Settings → Secrets → New repository secret, имя `SUPABASE_ACCESS_TOKEN`, значение — токен из https://supabase.com/dashboard/account/tokens

**Вручную** (из папки restodocks_flutter):
```bash
cd restodocks_flutter
npx supabase functions deploy --project-ref osglfptwbuqqmqunttha
```

## 6. AI чеклист — предпочтение Gemini

Если GigaChat недоступен из региона Supabase (EarlyDrop в логах), установите в секретах:

| Имя | Значение |
|-----|----------|
| `AI_PROVIDER` | `gemini` |

При наличии `GEMINI_API_KEY` функция будет использовать Gemini (обычно быстрее из ap-northeast-1).
