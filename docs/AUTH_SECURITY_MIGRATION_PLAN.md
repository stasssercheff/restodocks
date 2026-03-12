# План миграции: безопасный доступ к ТТК через Supabase Auth

## Текущее состояние

- **Supabase Auth** — владельцы и новые сотрудники (регистрация через Auth) получают JWT, RLS работает.
- **Legacy** — сотрудники, вошедшие через `authenticate-employee` (BCrypt), не имеют Supabase JWT. Сессия хранится в SecureStorage (employee_id + establishment_id). Запросы к Supabase идут с ролью **anon**.
- **tech_cards** — в `restodocks_flutter/supabase` есть политика `anon_select_tech_cards` (SELECT для всех). Любой клиент с anon key может читать все ТТК.

## Цель

Чтобы RLS ограничивал доступ по `establishment_id`, все запросы должны идти с ролью `authenticated` и валидным JWT (auth.uid() = employee или через auth_user_id).

## План поэтапно

### Фаза 0: Подготовка (без изменений логики)

- [ ] Проверить текущую схему БД: есть ли `employees.auth_user_id`, какие политики для tech_cards.
- [ ] Убедиться, что `current_user_establishment_ids()` учитывает и `employees.id = auth.uid()`, и `employees.auth_user_id = auth.uid()` (если колонка есть).

### Фаза 1: Связка legacy-сотрудников с auth.users

1. Добавить колонку `employees.auth_user_id` (если её нет) — nullable.
2. Обновить `current_user_establishment_ids()`:
   ```sql
   SELECT establishment_id FROM employees WHERE id = auth.uid() OR auth_user_id = auth.uid()
   UNION
   SELECT id FROM establishments WHERE owner_id = auth.uid() OR owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid());
   ```
3. Новая Edge Function `create-auth-for-legacy-employee`:
   - Вход: email, password, employee_id (после успешной проверки пароля).
   - Проверяет: employee существует, пароль верен (или получает это от authenticate-employee).
   - Создаёт `auth.users` через `supabase.auth.admin.createUser({ email, password, email_confirm: true })`.
   - Обновляет `employees.auth_user_id = newAuthUser.id`.
   - Возвращает `{ ok: true }`.

4. Изменить `authenticate-employee`:
   - После успешной проверки пароля: проверить `employees.auth_user_id`.
   - Если NULL — создать auth user, обновить auth_user_id, вернуть `{ employee, establishment, authUserCreated: true }`.
   - Иначе — вернуть как сейчас `{ employee, establishment }`.

5. Flutter: после успешного `authenticate-employee`:
   - Если `authUserCreated == true` → вызвать `signInWithPassword(email, password)`.
   - Если signIn успешен → сессия Supabase, дальше используется `_loadCurrentUserFromAuth()`.
   - Если signIn неуспешен → продолжать legacy (store employee_id, establishment_id). Логика входа не ломается.

### Фаза 2: Сужение anon для tech_cards

- Убрать `anon_select_tech_cards` (и аналогичные anon-политики для ТТК).
- Проверить на staging, что пользователи с Supabase Auth видят свои ТТК.
- Legacy-пользователи без JWT перестанут видеть ТТК через anon — поэтому важно, чтобы Фаза 1 перевела их на Auth при следующем входе.

### Фаза 3: Проверка и мониторинг

- Убедиться, что все сценарии входа работают.
- Убедиться, что RLS для tech_cards, employees, establishments ограничивает данные по establishment.

## Риски

| Фаза | Риск | Митигация |
|------|------|-----------|
| 1 | Ошибка при создании auth user | Fallback на legacy — вход продолжает работать |
| 1 | Конфликт email (уже есть в auth.users) | Проверять перед createUser; если есть — пробовать signIn |
| 2 | Legacy-пользователи без auth перестают видеть ТТК | Фаза 1 должна создать auth при первом входе; для старых сессий — потребуется повторный вход |
| 2 | RLS блокирует легитимный доступ | Тестировать на staging перед prod |

## Порядок внедрения

1. Реализовать Фазу 1.
2. Задеплоить, протестировать вход (Supabase Auth и legacy).
3. Убедиться, что после входа через legacy при следующем запуске создаётся auth и signIn срабатывает.
4. Только после стабилизации — Фаза 2 (снятие anon для tech_cards).

---

## Технический аудит (замечания)

### 1. Fallback на legacy — критичен

Во Flutter Web сессии могут вести себя нестабильно. Fallback на старую схему (employee_id + establishment_id в storage) при неудаче signIn позволяет не заблокировать поваров на кухне, если Supabase Auth «чихнёт» при первом деплое. У нас: при `authUserCreated` вызывается `signInWithEmail`; при ошибке — продолжаем с legacy (сохраняем employee/establishment, логируем).

### 2. Уникальность auth_user_id

Один аккаунт Auth не должен привязываться к двум разным employees. Добавлен UNIQUE-индекс на `employees.auth_user_id` (миграция `20260310170000_employees_auth_user_id_unique.sql`). Перед применением: убедиться, что в prod нет дубликатов:
```sql
SELECT auth_user_id, COUNT(*) FROM employees WHERE auth_user_id IS NOT NULL GROUP BY auth_user_id HAVING COUNT(*) > 1;
```

### 3. Риск «белого экрана» при сужении anon

При Phase 2 (снятие anon для tech_cards) важно: загрузка при инициализации (до входа) **не должна** требовать tech_cards. Проверено:
- Экран логина — только форма; employees/establishments не нужны до ввода пароля.
- `_restoreSession` (legacy) читает только `employees` и `establishments` — у них anon-политики **остаются**.
- tech_cards читаются уже после входа и перехода на home/tech-cards. К этому моменту у legacy после Phase 1 должен быть JWT (signIn при первом входе).

То есть инициализация приложения не использует tech_cards до логина — риск «белого экрана» по этой части отсутствует. Не убирать anon с `employees` и `establishments`, пока все пользователи не на Auth.

---

## Пароль только в Auth (unified)

Пароль хранится и проверяется только в Supabase Auth. `employees.password_hash` используется только для первого входа legacy-пользователя (без auth_user_id).

**authenticate-employee:** если у сотрудника есть `auth_user_id` → не проверяем `password_hash`, возвращаем 401. Пользователь должен входить через Supabase Auth.

**reset-password:** если `auth_user_id` есть → обновляем только Auth. Иначе (legacy) → обновляем только `password_hash`.

Регистрация с подтверждением по почте не затронута — идёт через Auth.
