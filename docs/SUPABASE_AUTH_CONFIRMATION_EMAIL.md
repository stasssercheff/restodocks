# Письмо со ссылкой подтверждения

**С сентября 2025:** ссылка подтверждения добавляется в письмо с данными регистрации (PIN, логин) через `send-registration-email`. Используется `generateLink` + Resend — **настройка Hook или SMTP не нужна**.

Письмо с PIN и ссылкой подтверждения приходит одним письмом через Resend (если при регистрации включён Confirm email и сессии нет).

## Обязательно

- **Authentication** → **Auth Providers** → **Email** → **Confirm email** = включён
- **Authentication** → **URL Configuration** → **Redirect URLs** = `https://restodocks.pages.dev`, `https://restodocks.com`, etc.
