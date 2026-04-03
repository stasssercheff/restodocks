# Письма при регистрации владельца / соучредителя

## Два письма (как задумано)

1. **Данные (PIN, логин, заведение)** — Edge Function `send-registration-email`, тип `owner`, через Resend. Вызывается из приложения после `signUp`.
2. **Ссылка подтверждения email** — отправляет **Supabase Auth** при включённом Confirm email:
   - **Рекомендуется:** [Send Email Hook](AUTH_SEND_EMAIL_HOOK_SETUP.md) → функция `auth-send-email` → то же Resend, русский текст, ссылка на `https://restodocks.com/auth/confirm-click?...` (как раньше во втором письме из `send-registration-email`).
   - Если Hook **не** подключён — используется шаблон из **Authentication → Email Templates** (часто английский от `mail.app.supabase.io`). Настройте шаблон **Confirm signup** под Restodocks или подключите Hook.

Дублирующий вызов `confirmation_only` из Flutter сразу после `signUp` **не делаем** — иначе два одинаковых письма с ссылкой (Hook + Edge). Повторная отправка — экран подтверждения и вход: `sendConfirmationLinkRequest` (см. `ConfirmEmailScreen`, `login_screen`).

## Обязательно

- **Authentication** → **Email** → **Confirm email** = включён
- **Authentication** → **URL Configuration** → **Redirect URLs** = `https://restodocks.com`, и т.д.
