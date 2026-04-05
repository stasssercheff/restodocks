-- =============================================================================
-- Как проверять IAP с ОДНИМ телефоном и без «десяти почт»
-- =============================================================================
-- 1) Apple ID для покупки в TestFlight — это не то же самое, что логин Restodocks.
--    Подписка в Sandbox привязана к Apple ID. Несколько учёток Restodocks на одном
--    устройстве возможны: разные email в приложении, один и тот же или разные
--    Sandbox Apple ID в настройках Media & Purchases (для тестов).
--
-- 2) «Уже есть подписка» в системном окне Apple — нормально для повторного теста:
--    - Настройки → Apple ID → Подписки → отменить тестовую подписку Restodocks, ИЛИ
--    - App Store Connect → Users and Access → Sandbox → завести НОВЫЙ Sandbox Apple ID
--      (это бесплатно, не нужен второй телефон) и войти им в Sandbox на устройстве.
--
-- 3) Один и тот же аккаунт Restodocks + одно заведение: сервер запоминает цепочку Apple.
--    Чтобы снова прогнать «как первый раз» на бэте, используйте:
--    - Секреты Edge: IAP_BILLING_TEST_ESTABLISHMENT_IDS=<uuid заведения> и опционально
--      IAP_BILLING_TEST_RESET_MINUTES=3  (через N минут после успешной верификации Edge
--      сбрасывает Pro и привязку — см. код billing-verify-apple), ИЛИ
--    - Скрипт reset_establishment_billing_by_owner_email.sql (ручной сброс в БД).
--
-- 4) Новые email для Restodocks без новых ящиков: алиасы (например user+test1@yandex.ru),
--    если ваш провайдер поддерживает «+», или отдельные тестовые ящики только для Auth.
--
-- 5) Ошибки HTTP 500 / Edge — это не «всё уже куплено», а баг/деплой/миграции:
--    логи функции billing-verify-apple в Supabase, выкатить актуальный Edge.
-- =============================================================================
--
-- Тестовый режим Edge `billing-verify-apple` (повторные прогонки покупки на TestFlight):
-- В Supabase → Project Settings → Edge Functions → Secrets:
--   IAP_BILLING_TEST_ESTABLISHMENT_IDS=<uuid_заведения>[,uuid2,...]
--   IAP_BILLING_TEST_RESET_MINUTES=3   (опционально, по умолчанию 3)
-- Нужны миграции: apple_iap_subscription_claims, iap_billing_test_state.
--
-- -----------------------------------------------------------------------------
-- Секрет (нужен именно id ЗАВЕДЕНИЯ из public.establishments):
--   IAP_BILLING_TEST_ESTABLISHMENT_IDS=<establishment_uuid>
--   IAP_BILLING_TEST_RESET_MINUTES=3
--
-- НЕ ПУТАТЬ: UUID в Supabase → Authentication → Users — это id ПОЛЬЗОВАТЕЛЯ
-- (auth.users / employees.id), а не establishments.id. Если подставить User UID
-- в секрет или в where establishments.id — запросы дадут 0 строк.
--
-- Владелец и подчинённые: регистрируются разные роли, у каждого свой User UID и
-- строка в public.employees. Подписка Pro / IAP на стороне сервера — у заведения
-- (establishments); оплату в App Store делает владелец, сотрудники не «покупают»
-- отдельную подписку на то же заведение. Секрет IAP_BILLING_TEST_* — всё равно
-- про establishment_id (обычно тот заведение, где тестируете покупку как владелец).
-- Запрос ниже по User UID работает для любой роли (owner, шеф, зал и т.д.).
-- Примеры с email masurfaker@yandex.ru — только удобный поиск заведения владельца;
-- для другого человека подставьте его email или его User UID.
-- -----------------------------------------------------------------------------
-- Сначала найти establishment_id в ЭТОМ проекте.
-- Подставлено: User UID (Authentication → Users) = 955f20fc-aaa7-4d5e-8ffc-8d42968857dd
-- Для другого аккаунта — поиск/замена по этому uuid в файле.
-- (Плейсхолдеры вроде <PASTE_...> в PostgreSQL не являются валидным uuid.)

-- По User UID из карточки пользователя (тот же UUID, что в Authentication → Users):
with p as (
  select '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid as auth_user_uid
)
select e.id   as establishment_id,
       e.name,
       emp.id as employee_row_id,
       emp.auth_user_id,
       emp.roles
  from public.establishments e
 inner join public.employees emp on emp.establishment_id = e.id
 cross join p
 where emp.id = p.auth_user_uid
    or emp.auth_user_id = p.auth_user_uid;

-- По email владельца (колонка owner_id → auth.users):
select e.id, e.name, u.email
  from public.establishments e
 inner join auth.users u on u.id = e.owner_id
 where lower(trim(u.email)) = lower(trim('masurfaker@yandex.ru'));

-- Тот же человек как owner в employees (на случай расхождений с owner_id):
select e.id, e.name, emp.email, emp.roles
  from public.establishments e
 inner join public.employees emp on emp.establishment_id = e.id
 where lower(trim(emp.email)) = lower(trim('masurfaker@yandex.ru'))
   and 'owner' = any (coalesce(emp.roles, array[]::text[]));

-- -----------------------------------------------------------------------------
-- Проверка заведения этого же пользователя (establishment_id берётся из employees).
-- Если у пользователя несколько заведений — в подзапросе limit 1 берётся одно (детерминировано по id).
-- roles — TEXT[]: проверяем через ANY.

-- Владелец + сотрудник с ролью owner:
with p as (
  select (
    select emp.establishment_id
      from public.employees emp
     where emp.id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
        or emp.auth_user_id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
     order by emp.establishment_id
     limit 1
  ) as establishment_uid
)
select e.id,
       e.name,
       e.owner_id,
       emp.id as employee_id,
       emp.auth_user_id,
       emp.roles
  from public.establishments e
 inner join public.employees emp
    on emp.establishment_id = e.id
 cross join p
 where e.id = p.establishment_uid
   and 'owner' = any (coalesce(emp.roles, array[]::text[]));

-- A) Есть ли заведение с этим id?
with p as (
  select (
    select emp.establishment_id
      from public.employees emp
     where emp.id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
        or emp.auth_user_id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
     order by emp.establishment_id
     limit 1
  ) as establishment_uid
)
select e.id, e.name, e.owner_id
  from public.establishments e
 cross join p
 where e.id = p.establishment_uid;

-- B) Все сотрудники этого заведения:
with p as (
  select (
    select emp.establishment_id
      from public.employees emp
     where emp.id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
        or emp.auth_user_id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
     order by emp.establishment_id
     limit 1
  ) as establishment_uid
)
select emp.id, emp.auth_user_id, emp.email, emp.roles, emp.establishment_id
  from public.employees emp
 cross join p
 where emp.establishment_id = p.establishment_uid;

-- -----------------------------------------------------------------------------
-- Только заведения, где этот пользователь — owner (если нужен один id для IAP):
with p as (
  select '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid as auth_user_uid
)
select e.id as establishment_id,
       e.name
  from public.establishments e
 inner join public.employees emp
    on emp.establishment_id = e.id
 cross join p
 where (emp.id = p.auth_user_uid
    or emp.auth_user_id = p.auth_user_uid)
   and 'owner' = any (coalesce(emp.roles, array[]::text[]))
 limit 5;

-- -----------------------------------------------------------------------------
-- Строки для Edge Functions → Secrets (establishment_id из employees этого User UID):
select 'IAP_BILLING_TEST_ESTABLISHMENT_IDS=' || eid::text as secret_line_1,
       'IAP_BILLING_TEST_RESET_MINUTES=3' as secret_line_2
  from (
    select emp.establishment_id as eid
      from public.employees emp
     where emp.id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
        or emp.auth_user_id = '955f20fc-aaa7-4d5e-8ffc-8d42968857dd'::uuid
     order by emp.establishment_id
     limit 1
  ) t;
