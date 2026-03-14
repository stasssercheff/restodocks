# authenticate-employee 401 — чеклист отладки

При 401 на `authenticate-employee` (даже при правильном пароле) проверь по порядку.

## 1. Supabase → Edge Functions → authenticate-employee → Logs

- **Где:** Supabase Dashboard → Edge Functions → `authenticate-employee` → Logs
- **Смотреть:** В момент попытки входа — появляются ли логи
- **Ожидаемо:**
  - `[authenticate-employee] Attempt for email=...` — запрос доходит
  - `No active employees found` → 401 (нет сотрудника с таким email)
  - `Password mismatch` → 401 (неверный пароль)
  - `Password OK` → 200 (успех)

**Если логов нет** — запрос не доходит до функции (proxy/сеть, неправильный URL).

---

## 2. Supabase Dashboard → Logs (общие)

- **Где:** Supabase Dashboard → Logs (фильтр по времени)
- **Фильтр:** Ищи 401, `authenticate-employee`, `functions`
- **Смотреть:** Ответ сервера, стек ошибок, тело запроса

---

## 3. Network в браузере (F12 → Network)

- **URL:** `https://osglfptwbuqqmqunttha.supabase.co/functions/v1/authenticate-employee`
- **Метод:** POST
- **Headers:** `Content-Type: application/json`, `apikey`, `Authorization: Bearer <anon_key>`
- **Body:** `{"email":"...","password":"..."}`

**Проверить:**
- Статус ответа (401, 500, CORS blocked)
- Response body: `{"error":"invalid_credentials"}` или другое
- Нет ли CORS / (blocked) / net::ERR_*

---

## 4. Redirect URLs (Supabase Auth)

- **Где:** Supabase Dashboard → Authentication → URL Configuration → Redirect URLs
- **Должны быть:**
  - `https://restodocks.com`
  - `https://restodocks.com/**`
  - `https://www.restodocks.com`
  - `https://www.restodocks.com/**`
  - `https://restodocks.pages.dev`
  - `https://restodocks.pages.dev/**`
  - `https://restodocks-2u8.pages.dev`
  - `https://restodocks-2u8.pages.dev/**`

**Site URL** = `https://restodocks.com` (или основной домен)

---

## 5. CORS (Supabase API)

- **Где:** Supabase Dashboard → Settings → API (или Data API)
- **Allowed Origins / CORS:** Добавь:
  - `https://restodocks.com`
  - `https://www.restodocks.com`
  - `https://restodocks.pages.dev`
  - `https://restodocks-2u8.pages.dev`

---

## 6. Cloudflare: Bypass cache

Если 401 «случайный» (то работает, то нет) — может кешироваться старый ответ.

- **Где:** Cloudflare → домен restodocks.com → Rules → Configuration Rules
- **Правило:** Bypass cache для hostname `restodocks.com`
- **Детали:** [CLOUDFLARE_RESTODOCKS_COM_FIX.md](CLOUDFLARE_RESTODOCKS_COM_FIX.md)

---

## 7. Retry в приложении

Приложение делает до 3 попыток при 401 + `invalid_credentials` (proxy может обрывать первый запрос).

Если после нескольких попыток всё равно 401 — значит, причина не в proxy, а в логике (пароль, email, auth_user_id).

---

## Типичные сценарии 401

| Сообщение в логах | Причина |
|-------------------|---------|
| No active employees found | Email нет в `employees` или `is_active=false` |
| Password mismatch | Неверный пароль (или plaintext hash — сброс через reset flow) |
| Employee has auth_user_id — use Supabase Auth | Входить через Supabase Auth, не legacy |
| No matching password for any employee | Перебрали всех, пароль не подошёл |
