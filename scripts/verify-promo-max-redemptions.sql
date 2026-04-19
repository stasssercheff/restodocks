-- Проверка ПОСЛЕ применения миграции (это НЕ сама миграция).
-- Сначала выполни в SQL Editor содержимое файла:
--   supabase/migrations/20260629120000_promo_max_redemptions.sql
-- (копия: restodocks_flutter/supabase/migrations/20260629120000_promo_max_redemptions.sql)
--
-- Самая короткая проверка «колонка на месте»: scripts/quick-check-promo-max-redemptions-column.sql
--
-- Запуск этого скрипта: Supabase Dashboard → SQL Editor.
--
-- Ожидаемо: все блоки ниже без «проблемных» строк в финальных SELECT.
-- Ручная отметка is_used без строк в promo_code_redemptions — старый сценарий;
--   такие строки попадут в «рассинхрон», это нормально, если вы так помечали коды.

-- =============================================================================
-- 0) Предусловие: колонка уже есть (если false — миграция ещё не применена)
-- =============================================================================
SELECT EXISTS (
  SELECT 1
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'promo_codes'
    AND column_name = 'max_redemptions'
) AS max_redemptions_column_exists;

-- Если false — сначала миграция 20260629120000. Блоки 4 и 6 ниже безопасны: без колонки
-- вернут пояснение, а не ERROR 42703.

-- =============================================================================
-- 1) Колонка max_redemptions
-- =============================================================================
SELECT column_name,
       data_type,
       is_nullable,
       column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'promo_codes'
  AND column_name = 'max_redemptions';

-- Ожидание: одна строка, NOT NULL, default 1 (или эквивалент).

-- =============================================================================
-- 2) Триггеры на promo_code_redemptions
-- =============================================================================
SELECT t.tgname,
       c.relname AS on_table,
       p.proname AS function_name
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND c.relname = 'promo_code_redemptions'
  AND NOT t.tgisinternal
ORDER BY t.tgname;

-- Ожидание: trg_promo_code_redemptions_limit (BEFORE INSERT), trg_promo_code_redemptions_sync (AFTER ...).

-- =============================================================================
-- 3) В теле функций есть учёт max_redemptions (дымовой тест после деплоя определений)
-- =============================================================================
SELECT p.proname,
       (pg_get_functiondef(p.oid) LIKE '%max_redemptions%') AS body_mentions_max_redemptions
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'promo_code_redemptions_limit_before',
    'promo_code_redemptions_sync_promo_row',
    'register_company_with_promo',
    'apply_promo_to_establishment_for_owner'
  )
ORDER BY p.proname;

-- Ожидание: четыре строки, все body_mentions_max_redemptions = true.
-- Пока миграция не применена — будет false (это ожидаемо).

-- =============================================================================
-- 4) Согласованность is_used с redemptions (для строк, где есть погашения)
--     Динамический SQL: без колонки max_redemptions запрос не парсится заранее.
-- =============================================================================
DROP TABLE IF EXISTS _verify_promo_block4;
CREATE TEMP TABLE _verify_promo_block4 (
  id bigint,
  code text,
  max_redemptions int,
  redemption_count int,
  is_used_in_db boolean,
  expected_is_used boolean
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'promo_codes'
      AND column_name = 'max_redemptions'
  ) THEN
    INSERT INTO _verify_promo_block4 (id, code)
    VALUES (NULL, '— блок пропущен: нет колонки max_redemptions, сначала миграция 20260629120000 —');
    RETURN;
  END IF;

  INSERT INTO _verify_promo_block4
  EXECUTE $sql$
    SELECT
      pc.id,
      pc.code::text,
      pc.max_redemptions,
      COALESCE(r.cnt, 0)::int,
      pc.is_used,
      (COALESCE(r.cnt, 0) >= pc.max_redemptions)
    FROM public.promo_codes pc
    LEFT JOIN (
      SELECT promo_code_id, COUNT(*)::int AS cnt
      FROM public.promo_code_redemptions
      GROUP BY promo_code_id
    ) r ON r.promo_code_id = pc.id
    WHERE COALESCE(r.cnt, 0) > 0
      AND pc.is_used IS DISTINCT FROM (COALESCE(r.cnt, 0) >= pc.max_redemptions)
    ORDER BY pc.id
  $sql$;
END $$;

SELECT * FROM _verify_promo_block4;

-- Ожидание: 0 строк с реальными id, либо одна строка-пояснение о пропуске.
-- Если есть строки с id — пересчитать или разобрать вручную.

-- =============================================================================
-- 5) Согласованность для кодов без redemptions: is_used должен быть false
--    (если вы нигде вручную не ставили is_used=true без погашения — иначе пропустите)
-- =============================================================================
SELECT pc.id,
       pc.code,
       pc.is_used,
       pc.used_by_establishment_id
FROM public.promo_codes pc
WHERE NOT EXISTS (SELECT 1 FROM public.promo_code_redemptions r WHERE r.promo_code_id = pc.id)
  AND pc.is_used = true
ORDER BY pc.id;

-- Ожидание: либо 0 строк, либо только осознанные «ручные» пометки без redemptions.

-- =============================================================================
-- 6) Лимиты в допустимом диапазоне
-- =============================================================================
DROP TABLE IF EXISTS _verify_promo_block6;
CREATE TEMP TABLE _verify_promo_block6 (
  id bigint,
  code text,
  max_redemptions int
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'promo_codes'
      AND column_name = 'max_redemptions'
  ) THEN
    INSERT INTO _verify_promo_block6 (id, code)
    VALUES (NULL, '— блок пропущен: нет колонки max_redemptions, сначала миграция 20260629120000 —');
    RETURN;
  END IF;

  INSERT INTO _verify_promo_block6
  EXECUTE $sql$
    SELECT pc.id, pc.code::text, pc.max_redemptions
    FROM public.promo_codes pc
    WHERE pc.max_redemptions < 1 OR pc.max_redemptions > 100000
    ORDER BY pc.id
  $sql$;
END $$;

SELECT * FROM _verify_promo_block6;

-- Ожидание: 0 строк с реальными id, либо одна строка-пояснение о пропуске.
