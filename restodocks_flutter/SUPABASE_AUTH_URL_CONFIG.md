# Настройка Supabase Auth для подтверждения email

## Проблема
После регистрации пользователь переходит по ссылке из письма, но Supabase не подтверждает email. При попытке входа показывается «Неверный пароль» — это общая ошибка, Supabase также возвращает её, когда email ещё не подтверждён.

## Причина
Неправильно настроены **Site URL** и **Redirect URLs** в Supabase Dashboard. Ссылка подтверждения должна вести на ваш сайт, и URL должен быть в списке разрешённых.

## Решение

### 1. Откройте URL Configuration в Supabase
1. Войдите в [Supabase Dashboard](https://supabase.com/dashboard)
2. Выберите проект
3. **Authentication** → **URL Configuration**

### 2. Установите Site URL
- **Site URL**: `https://restodocks.com` (основной домен без www)
- Для входа с restodocks.com в адресной строке Site URL должен быть без www.

### 3. Добавьте Redirect URLs
В поле **Redirect URLs** добавьте все домены, где размещено приложение (каждый с новой строки):

```
https://restodocks.pages.dev
https://restodocks.pages.dev/**
https://restodocks.pages.dev/
https://*.pages.dev
https://*.pages.dev/**
https://www.restodocks.com
https://www.restodocks.com/
https://restodocks.com
https://restodocks.com/
https://restodocks.vercel.app
https://restodocks.vercel.app/
https://demo.restodocks.com
https://demo.restodocks.com/**
https://*.netlify.app
http://localhost:3000
http://localhost:8080
http://127.0.0.1:3000
http://127.0.0.1:8080
```

**Важно при переносе хостинга:** каждый новый домен (Vercel, Netlify, Cloudflare Pages и т.д.) нужно добавить сюда. Иначе Auth может давать «неверный пароль» или другие ошибки.

### 4. Сохраните изменения
Нажмите **Save**.

### 5. Проверка
1. Зарегистрируйте нового сотрудника (с новым email)
2. Откройте письмо подтверждения
3. Нажмите на ссылку
4. Должно открыться приложение с авторизацией (или страница входа — тогда войдите с паролем)
5. Вход должен пройти успешно

## Задержка писем (минуты вместо секунд)

Если письмо подтверждения приходит с задержкой 5+ минут:

1. **Supabase Dashboard** → **Project Settings** → **Auth** → **SMTP Settings**
2. Включите **Custom SMTP** и настройте:
   - Resend, SendGrid, Mailgun или ваш SMTP
   - Письма будут отправляться быстрее (обычно секунды)

Без настройки Supabase использует встроенный сервис, который может быть медленным.

## Дополнительно
- В коде используется `emailRedirectTo` — при signUp передаётся URL текущего сайта (на web — `Uri.base.origin`).
- Если Site URL и Redirect URLs настроены верно, Supabase добавляет токены в URL при редиректе, и Flutter с `detectSessionInUri: true` автоматически создаёт сессию.
