# billing-verify-apple: что сделано и что сделать вручную

Проект Supabase (beta), с которым связан CLI: **`osglfptwbuqqmqunttha`**.

---

## Уже сделано из репозитория (автоматически)

1. **Деплой Edge Function `billing-verify-apple`**  
   Команда (из корня репо, при связанном `supabase link`):

   ```bash
   cd /path/to/Restodocks
   supabase functions deploy billing-verify-apple
   ```

   Проверка в Dashboard:  
   [Edge Functions — billing-verify-apple](https://supabase.com/dashboard/project/osglfptwbuqqmqunttha/functions)

2. **Полный `supabase db push --include-all` не выполнен до конца** — остановился на миграции промокодов (`PROMO_USED` при переносе данных). Это **не** связано с IAP. Историю миграций на проде/beta нужно привести в порядок отдельно (или починить миграцию и повторить push).

---

## Что сделать вам (обязательно для устранения HTTP 500)

### A. Таблицы в БД (если их ещё нет)

Выполните в **SQL Editor** того же проекта файл:

- [`apply-iap-billing-tables-only.sql`](apply-iap-billing-tables-only.sql)

Затем проверка:

- [`verify-iap-billing-db.sql`](verify-iap-billing-db.sql) — обе колонки должны быть `true`.

Без `apple_iap_subscription_claims` Edge при активной подписке часто падает на шагах с `INSERT`/`SELECT` по этой таблице → **500**.

---

### B. Секреты Edge (Project Settings → Edge Functions → Secrets)

| Имя секрета | Назначение |
|-------------|------------|
| **`APPLE_IAP_SHARED_SECRET`** | Общий ключ подписки из **App Store Connect** → ваше приложение → **In-App Purchase** → **App-Specific Shared Secret**. Без него `verifyReceipt` не работает; в коде при отсутствии всех трёх переменных (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `APPLE_IAP_SHARED_SECRET`) возвращается **500** с текстом `Server configuration error`. |
| **`SUPABASE_URL`** | Обычно подставляется платформой; если пусто в среде функции — тоже конфигурационная ошибка. |
| **`SUPABASE_SERVICE_ROLE_KEY`** | Service role для Edge (как в документации Supabase). |

Опционально для **тестового сброса** подписки на beta:

| Имя | Пример |
|-----|--------|
| **`IAP_BILLING_TEST_ESTABLISHMENT_IDS`** | Один или несколько UUID через запятую: **`public.establishments.id`**, не User UID из Auth. |
| **`IAP_BILLING_TEST_RESET_MINUTES`** | Например `3` (по умолчанию в коде тоже 3). |

После изменения секретов **перезапускать функцию не нужно** — следующий вызов подхватит новые значения.

---

### C. Логи с текстом ошибки (не только Boot/Shutdown)

1. Откройте [Logs — billing-verify-apple](https://supabase.com/dashboard/project/osglfptwbuqqmqunttha/functions/billing-verify-apple/logs) (или Logs → фильтр по имени функции).
2. В поиске введите: **`billing-verify-apple`** или **`error`** или **`verifyReceipt`**.
3. В колонке **event_message** ищите строки с **`console.error`** из кода, например:  
   - `billing-verify-apple: Apple verifyReceipt failed`  
   - `billing-verify-apple: establishments update failed`  
4. Если при **500** в ответе JSON есть поля **`error`**, **`code`**, **`hint`** — скопируйте их; в Flutter в dev-логе бывает строка вида  
   `IAP billing-verify-apple failed: 500 {error: ...}`.

---

### D. Проверка с клиента после настройки

1. Войти в приложение как **owner** нужного заведения.  
2. Оплата / восстановление покупки → смотреть сеть или лог:  
   `POST .../functions/v1/billing-verify-apple` → статус **200** и тело с `"ok": true`.

Если снова **500** — пришлите **полное тело ответа** (JSON) и строку из логов Edge с `error` / `console.error`.

---

## Кратко: типичные причины 500 после деплоя функции

1. Нет таблицы **`apple_iap_subscription_claims`** (или ошибка прав) — применить `apply-iap-billing-tables-only.sql`.  
2. Нет или неверный **`APPLE_IAP_SHARED_SECRET`**.  
3. Ошибка **`UPDATE establishments`** (нет колонки `subscription_type` / `pro_paid_until`, constraint) — смотреть `code`/`hint` в JSON ответа.  
4. Исключение в `catch` — текст в `{ "error": "..." }` в теле ответа.

---

## Повторный деплой функции (когда меняете только код)

```bash
cd /path/to/Restodocks
supabase functions deploy billing-verify-apple
```

Убедитесь, что `supabase link` указывает на тот же `project_ref`, что и URL в приложении (`osglfptwbuqqmqunttha`).
