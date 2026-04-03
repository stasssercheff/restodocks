# Письма при регистрации владельца / соучредителя / сотрудника

## Два письма (как задумано)

1. **Данные (PIN, логин, заведение)** — Edge Function `send-registration-email`, тип `owner` / `employee` / `co_owner`, через Resend. Вызывается из приложения после `signUp` (или после подтверждения для отложенного co-owner).
2. **Ссылка подтверждения email** — приложение после `signUp` (если нет сессии) вызывает Edge **`send-registration-email`** с типом `confirmation_only` через **`EmailService.sendConfirmationLinkRequest`** (Resend, `generateLink` + запас `auth.resend`). Иначе пользователь часто получает только письмо с данными, а письмо от Auth/Hook не приходит.

Дополнительно Auth может слать своё письмо (Hook или шаблоны). Если настроены и Hook, и вызов из приложения, теоретически возможны **два** письма со ссылкой — это компромисс ради гарантированной доставки; при желании отключите дубль на стороне Auth или оставьте только один канал после проверки логов.

## Обязательно

- **Authentication** → **Email** → **Confirm email** = включён
- **Authentication** → **URL Configuration** → **Redirect URLs** = `https://restodocks.com`, и т.д.
