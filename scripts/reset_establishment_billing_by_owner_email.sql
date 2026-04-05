-- Сброс Pro / IAP / тестового таймера для аккаунта по email владельца.
-- Запуск: Supabase → SQL Editor → подставить email в v_email → выполнить весь блок.
-- Обновляет только те колонки establishments, которые реально есть в БД (если нет pro_paid_until — не падает).
-- Важно: подписка в App Store / Sandbox остаётся на стороне Apple.

DO $$
DECLARE
  v_email text := 'masurfaker@yandex.ru';
  v_parts text[] := ARRAY[]::text[];
  v_sql text;
BEGIN
  CREATE TEMP TABLE _reset_est ON COMMIT DROP AS
  SELECT DISTINCT e.id
  FROM public.establishments e
  JOIN auth.users u ON u.id = e.owner_id AND lower(trim(u.email)) = lower(trim(v_email))
  UNION
  SELECT DISTINCT emp.establishment_id
  FROM public.employees emp
  WHERE lower(trim(emp.email)) = lower(trim(v_email))
    AND 'owner' = ANY (COALESCE(emp.roles, ARRAY[]::text[]));

  IF to_regclass('public.apple_iap_subscription_claims') IS NOT NULL THEN
    DELETE FROM public.apple_iap_subscription_claims c
    WHERE c.establishment_id IN (SELECT id FROM _reset_est);
  END IF;

  IF to_regclass('public.iap_billing_test_state') IS NOT NULL THEN
    DELETE FROM public.iap_billing_test_state t
    WHERE t.establishment_id IN (SELECT id FROM _reset_est);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'establishments' AND column_name = 'subscription_type'
  ) THEN
    v_parts := array_append(v_parts, 'subscription_type = ''free''');
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'establishments' AND column_name = 'pro_paid_until'
  ) THEN
    v_parts := array_append(v_parts, 'pro_paid_until = NULL');
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'establishments' AND column_name = 'pro_trial_ends_at'
  ) THEN
    v_parts := array_append(v_parts, 'pro_trial_ends_at = NULL');
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'establishments' AND column_name = 'updated_at'
  ) THEN
    v_parts := array_append(v_parts, 'updated_at = now()');
  END IF;

  IF array_length(v_parts, 1) IS NULL OR array_length(v_parts, 1) = 0 THEN
    RAISE EXCEPTION 'establishments: не найдено ни одной колонки для сброса (subscription_type / pro_* / updated_at)';
  END IF;

  v_sql := format(
    'UPDATE public.establishments e SET %s WHERE e.id IN (SELECT id FROM _reset_est)',
    array_to_string(v_parts, ', ')
  );

  EXECUTE v_sql;
END $$;

-- Проверка (опционально). Если нет колонок pro_* — не включайте их в SELECT:
-- SELECT e.id, e.subscription_type, e.updated_at
-- FROM public.establishments e
-- JOIN auth.users u ON u.id = e.owner_id AND lower(trim(u.email)) = lower(trim('masurfaker@yandex.ru'));
