-- =============================================================================
-- Ручное применение миграций (Supabase Dashboard → SQL → New query → Run)
--
-- Что это: объединённые миграции с 20260330190000 по 20260430180000 из
-- supabase/migrations/, в хронологическом порядке.
--
-- Зачем: команда `supabase db push` подключается к облачной Postgres напрямую
-- и записывает версии в supabase_migrations.schema_migrations. Если у вас
-- таймаут/нет пароля в SUPABASE_DB_PASSWORD — push «недоступен» с этой машины;
-- тогда этот файл выполняется вручную один раз (эквивалент по схеме, но без
-- записи в schema_migrations — при желании потом синхронизируйте историю push).
--
-- Выполняйте целиком одной кнопкой Run. Не дробите посередине тела $$ ... $$.
-- Если какой-то блок уже был применён, часть команд может выдать «already exists»
-- — смотрите текст ошибки и при необходимости закомментируйте завершившийся блок.
-- =============================================================================



-- -----------------------------------------------------------------------------
-- FROM: 20260330190000_get_establishment_products_rpc.sql
-- -----------------------------------------------------------------------------
-- RPC для фолбэка номенклатуры (ProductStore). Ранее существовала только в отдельном .sql без миграции → 404 на проде.
-- Доступ: владелец заведения ИЛИ активный сотрудник с привязкой auth_user_id (не только owner_id).

CREATE OR REPLACE FUNCTION public.get_establishment_products(est_id UUID)
RETURNS TABLE (
  product_id UUID,
  price NUMERIC,
  currency TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.id = est_id
      AND (
        e.owner_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.employees emp
          WHERE emp.establishment_id = e.id
            AND emp.auth_user_id = auth.uid()
            AND COALESCE(emp.is_active, true)
        )
      )
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT ep.product_id, ep.price, ep.currency
  FROM public.establishment_products ep
  WHERE ep.establishment_id = est_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_establishment_products(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_establishment_products(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_establishment_products(UUID) TO service_role;


-- -----------------------------------------------------------------------------
-- FROM: 20260330191000_employee_page_tour_seen.sql
-- -----------------------------------------------------------------------------
-- Синхрон с restodocks_flutter: таблица тура могла отсутствовать при деплое только из корневого supabase/migrations.

CREATE TABLE IF NOT EXISTS public.employee_page_tour_seen (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  page_key TEXT NOT NULL,
  seen_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(employee_id, page_key)
);

CREATE INDEX IF NOT EXISTS idx_employee_page_tour_seen_employee
  ON public.employee_page_tour_seen(employee_id);

ALTER TABLE public.employee_page_tour_seen ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Employee manages own tour progress" ON public.employee_page_tour_seen;
CREATE POLICY "Employee manages own tour progress"
  ON public.employee_page_tour_seen
  FOR ALL
  USING (
    employee_id IN (
      SELECT id FROM public.employees
      WHERE auth_user_id = auth.uid() OR id = auth.uid()
    )
  )
  WITH CHECK (
    employee_id IN (
      SELECT id FROM public.employees
      WHERE auth_user_id = auth.uid() OR id = auth.uid()
    )
  );


-- -----------------------------------------------------------------------------
-- FROM: 20260331000000_chat_rooms.sql
-- -----------------------------------------------------------------------------
-- Групповые чаты между сотрудниками заведения.

CREATE TABLE IF NOT EXISTS chat_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_establishment ON chat_rooms(establishment_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_created ON chat_rooms(created_at DESC);

COMMENT ON TABLE chat_rooms IS 'Групповые чаты заведения. name — переименовываемое название.';

CREATE TABLE IF NOT EXISTS chat_room_members (
  chat_room_id UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (chat_room_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_room_members_employee ON chat_room_members(employee_id);

CREATE TABLE IF NOT EXISTS chat_room_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_room_id UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  content TEXT NOT NULL DEFAULT '',
  image_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_room_messages_room ON chat_room_messages(chat_room_id);
CREATE INDEX IF NOT EXISTS idx_chat_room_messages_created ON chat_room_messages(created_at DESC);

COMMENT ON TABLE chat_room_messages IS 'Сообщения в групповом чате.';

-- RLS
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_room_messages ENABLE ROW LEVEL SECURITY;

-- Читать комнаты: только участники (через chat_room_members).
DROP POLICY IF EXISTS chat_rooms_select ON chat_rooms;
CREATE POLICY chat_rooms_select ON chat_rooms FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  );

-- Создавать комнаты: сотрудник своего заведения.
DROP POLICY IF EXISTS chat_rooms_insert ON chat_rooms;
CREATE POLICY chat_rooms_insert ON chat_rooms FOR INSERT TO authenticated
  WITH CHECK (
    created_by_employee_id = auth.uid()
    AND establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- Обновлять (переименование): только участник комнаты.
DROP POLICY IF EXISTS chat_rooms_update ON chat_rooms;
CREATE POLICY chat_rooms_update ON chat_rooms FOR UPDATE TO authenticated
  USING (
    id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  )
  WITH CHECK (true);

-- Удалять комнаты: только создатель (опционально; можно не давать).
-- Пока не добавляем DELETE policy — удаление только через каскад при удалении заведения.

-- Участники: читать/добавлять/удалять только свои записи или в комнатах, где состоишь.
DROP POLICY IF EXISTS chat_room_members_select ON chat_room_members;
CREATE POLICY chat_room_members_select ON chat_room_members FOR SELECT TO authenticated
  USING (
    chat_room_id IN (
      SELECT id FROM chat_rooms WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

-- Вставка: добавлять себя в комнату или создатель комнаты добавляет других участников.
DROP POLICY IF EXISTS chat_room_members_insert ON chat_room_members;
CREATE POLICY chat_room_members_insert ON chat_room_members FOR INSERT TO authenticated
  WITH CHECK (
    employee_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM chat_rooms cr
      WHERE cr.id = chat_room_members.chat_room_id AND cr.created_by_employee_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS chat_room_members_delete ON chat_room_members;
CREATE POLICY chat_room_members_delete ON chat_room_members FOR DELETE TO authenticated
  USING (employee_id = auth.uid());

-- Сообщения: читать только в комнатах, где участник; писать — только участник.
DROP POLICY IF EXISTS chat_room_messages_select ON chat_room_messages;
CREATE POLICY chat_room_messages_select ON chat_room_messages FOR SELECT TO authenticated
  USING (
    chat_room_id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS chat_room_messages_insert ON chat_room_messages;
CREATE POLICY chat_room_messages_insert ON chat_room_messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_employee_id = auth.uid()
    AND chat_room_id IN (
      SELECT chat_room_id FROM chat_room_members WHERE employee_id = auth.uid()
    )
  );

GRANT SELECT, INSERT, UPDATE ON chat_rooms TO authenticated;
GRANT SELECT, INSERT, DELETE ON chat_room_members TO authenticated;
GRANT SELECT, INSERT ON chat_room_messages TO authenticated;

-- Realtime для групповых сообщений
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE chat_room_messages;
EXCEPTION
  WHEN duplicate_object THEN
    NULL;
END
$$;


-- -----------------------------------------------------------------------------
-- FROM: 20260331010000_delete_establishment_chat_rooms.sql
-- -----------------------------------------------------------------------------
-- Удаление групповых чатов при удалении заведения (в _delete_establishment_cascade).

CREATE OR REPLACE FUNCTION public._delete_establishment_cascade(p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM establishments WHERE parent_establishment_id = p_establishment_id
  LOOP
    PERFORM _delete_establishment_cascade(r.id);
  END LOOP;

  DELETE FROM pending_owner_registrations WHERE establishment_id = p_establishment_id;
  DELETE FROM password_reset_tokens WHERE employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id);
  DELETE FROM co_owner_invitations WHERE establishment_id = p_establishment_id;
  DELETE FROM employee_direct_messages WHERE sender_employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id)
     OR recipient_employee_id IN (SELECT id FROM employees WHERE establishment_id = p_establishment_id);

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chat_room_messages') THEN
    DELETE FROM chat_room_messages WHERE chat_room_id IN (SELECT id FROM chat_rooms WHERE establishment_id = p_establishment_id);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chat_room_members') THEN
    DELETE FROM chat_room_members WHERE chat_room_id IN (SELECT id FROM chat_rooms WHERE establishment_id = p_establishment_id);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chat_rooms') THEN
    DELETE FROM chat_rooms WHERE establishment_id = p_establishment_id;
  END IF;

  DELETE FROM inventory_documents WHERE establishment_id = p_establishment_id;
  DELETE FROM order_documents WHERE establishment_id = p_establishment_id;
  DELETE FROM inventory_drafts WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_schedule_data WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_order_list_data WHERE establishment_id = p_establishment_id;
  DELETE FROM product_price_history WHERE establishment_id = p_establishment_id;
  DELETE FROM establishment_products WHERE establishment_id = p_establishment_id;
  DELETE FROM tt_ingredients WHERE tech_card_id IN (SELECT id FROM tech_cards WHERE establishment_id = p_establishment_id);
  DELETE FROM tech_cards WHERE establishment_id = p_establishment_id;
  DELETE FROM checklist_drafts WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklist_items WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklist_submissions WHERE checklist_id IN (SELECT id FROM checklists WHERE establishment_id = p_establishment_id);
  DELETE FROM checklists WHERE establishment_id = p_establishment_id;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'iiko_blank_storage') THEN
    DELETE FROM iiko_blank_storage WHERE establishment_id = p_establishment_id;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'iiko_products') THEN
    DELETE FROM iiko_products WHERE establishment_id = p_establishment_id;
  END IF;

  UPDATE establishments SET owner_id = NULL WHERE id = p_establishment_id;
  DELETE FROM employees WHERE establishment_id = p_establishment_id;
  DELETE FROM establishments WHERE id = p_establishment_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- FROM: 20260331020000_get_product_by_name_rpc.sql
-- -----------------------------------------------------------------------------
-- RPC для поиска продукта по нормализованному имени (lower(trim)).
-- Используется при 409 Conflict: продукт уже есть в БД, ищем его для маппинга ингредиентов.
CREATE OR REPLACE FUNCTION get_product_by_normalized_name(p_name text)
RETURNS products AS $$
  SELECT * FROM products WHERE lower(trim(name)) = lower(trim(p_name)) LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_product_by_normalized_name(text) TO authenticated;


-- -----------------------------------------------------------------------------
-- FROM: 20260332000000_nutrition_profiles_layer.sql
-- -----------------------------------------------------------------------------
-- Nutrition layer: stable system matching without changing user-visible product names
-- Adds:
--  - nutrition_profiles: canonical nutrition objects (KBJU + allergens)
--  - nutrition_aliases: normalized user/product inputs -> nutrition_profile_id
--  - product_nutrition_links: product -> nutrition_profile link with confidence/status
--  - nutrition_research_queue: periodic background re-check tasks

-- Ensure pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- nutrition_profiles
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.nutrition_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Canonical names (for debugging/UI/admin if needed)
  canonical_name text NOT NULL,
  canonical_name_ru text,
  canonical_name_en text,
  canonical_key text NOT NULL UNIQUE,

  -- Optional business grouping (e.g. vegetables/meat/etc.)
  category text,

  -- Nutrition per 100g
  calories real,
  protein real,
  fat real,
  carbs real,

  contains_gluten boolean,
  contains_lactose boolean,

  -- Metadata
  source text,
  source_ref text,
  confidence real,
  status text DEFAULT 'external_unverified',
  last_verified_at timestamptz,

  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nutrition_profiles_status ON public.nutrition_profiles(status);

-- -----------------------------------------------------------------------------
-- nutrition_aliases
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.nutrition_aliases (
  normalized_input text PRIMARY KEY,
  nutrition_profile_id uuid NOT NULL REFERENCES public.nutrition_profiles(id) ON DELETE CASCADE,

  raw_examples jsonb,
  confidence real,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nutrition_aliases_profile_id ON public.nutrition_aliases(nutrition_profile_id);

-- -----------------------------------------------------------------------------
-- product_nutrition_links
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.product_nutrition_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  nutrition_profile_id uuid NOT NULL REFERENCES public.nutrition_profiles(id) ON DELETE CASCADE,

  match_type text NOT NULL DEFAULT 'unmatched',
  match_confidence real,
  match_source text,

  normalized_query text,
  input_name_snapshot text,

  approved_by_user boolean NOT NULL DEFAULT false,
  approved_at timestamptz,

  last_checked_at timestamptz,
  recheck_after timestamptz,

  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),

  CONSTRAINT product_nutrition_links_product_id_unique UNIQUE (product_id)
);

CREATE INDEX IF NOT EXISTS idx_product_nutrition_links_profile_id ON public.product_nutrition_links(nutrition_profile_id);
CREATE INDEX IF NOT EXISTS idx_product_nutrition_links_recheck ON public.product_nutrition_links(recheck_after);

-- -----------------------------------------------------------------------------
-- nutrition_research_queue
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.nutrition_research_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  reason text NOT NULL,

  priority int NOT NULL DEFAULT 0,
  attempts int NOT NULL DEFAULT 0,
  max_attempts int NOT NULL DEFAULT 6,

  status text NOT NULL DEFAULT 'pending', -- pending/running/completed/failed
  next_retry_at timestamptz NOT NULL DEFAULT now(),
  locked_at timestamptz,
  worker_id text,
  last_error text,

  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),

  CONSTRAINT nutrition_research_queue_product_reason_unique UNIQUE (product_id, reason)
);

CREATE INDEX IF NOT EXISTS idx_nutrition_research_queue_pending ON public.nutrition_research_queue(status, next_retry_at);
CREATE INDEX IF NOT EXISTS idx_nutrition_research_queue_product ON public.nutrition_research_queue(product_id);

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
ALTER TABLE public.nutrition_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_nutrition_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_research_queue ENABLE ROW LEVEL SECURITY;

-- For compatibility: app can run under different roles during legacy/auth migration.
-- Allow SELECT for both anon and authenticated.
DROP POLICY IF EXISTS "anon_select_nutrition_profiles" ON public.nutrition_profiles;
CREATE POLICY "anon_select_nutrition_profiles" ON public.nutrition_profiles
  FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "auth_select_nutrition_profiles" ON public.nutrition_profiles;
CREATE POLICY "auth_select_nutrition_profiles" ON public.nutrition_profiles
  FOR SELECT TO authenticated USING (true);

-- Allow reads/writes from app background for both roles (upsert links/aliases).
DROP POLICY IF EXISTS "anon_write_nutrition_profiles" ON public.nutrition_profiles;
CREATE POLICY "anon_write_nutrition_profiles" ON public.nutrition_profiles
  FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_nutrition_profiles" ON public.nutrition_profiles;
CREATE POLICY "anon_update_nutrition_profiles" ON public.nutrition_profiles
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_write_nutrition_profiles" ON public.nutrition_profiles;
CREATE POLICY "auth_write_nutrition_profiles" ON public.nutrition_profiles
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_nutrition_profiles" ON public.nutrition_profiles;
CREATE POLICY "auth_update_nutrition_profiles" ON public.nutrition_profiles
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_select_nutrition_aliases" ON public.nutrition_aliases;
CREATE POLICY "anon_select_nutrition_aliases" ON public.nutrition_aliases
  FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "auth_select_nutrition_aliases" ON public.nutrition_aliases;
CREATE POLICY "auth_select_nutrition_aliases" ON public.nutrition_aliases
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "anon_write_nutrition_aliases" ON public.nutrition_aliases;
CREATE POLICY "anon_write_nutrition_aliases" ON public.nutrition_aliases
  FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_nutrition_aliases" ON public.nutrition_aliases;
CREATE POLICY "anon_update_nutrition_aliases" ON public.nutrition_aliases
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_write_nutrition_aliases" ON public.nutrition_aliases;
CREATE POLICY "auth_write_nutrition_aliases" ON public.nutrition_aliases
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_nutrition_aliases" ON public.nutrition_aliases;
CREATE POLICY "auth_update_nutrition_aliases" ON public.nutrition_aliases
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_select_product_nutrition_links" ON public.product_nutrition_links;
CREATE POLICY "anon_select_product_nutrition_links" ON public.product_nutrition_links
  FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "auth_select_product_nutrition_links" ON public.product_nutrition_links;
CREATE POLICY "auth_select_product_nutrition_links" ON public.product_nutrition_links
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "anon_write_product_nutrition_links" ON public.product_nutrition_links;
CREATE POLICY "anon_write_product_nutrition_links" ON public.product_nutrition_links
  FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_product_nutrition_links" ON public.product_nutrition_links;
CREATE POLICY "anon_update_product_nutrition_links" ON public.product_nutrition_links
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_write_product_nutrition_links" ON public.product_nutrition_links;
CREATE POLICY "auth_write_product_nutrition_links" ON public.product_nutrition_links
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_product_nutrition_links" ON public.product_nutrition_links;
CREATE POLICY "auth_update_product_nutrition_links" ON public.product_nutrition_links
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_select_nutrition_research_queue" ON public.nutrition_research_queue;
CREATE POLICY "anon_select_nutrition_research_queue" ON public.nutrition_research_queue
  FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "auth_select_nutrition_research_queue" ON public.nutrition_research_queue;
CREATE POLICY "auth_select_nutrition_research_queue" ON public.nutrition_research_queue
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "anon_write_nutrition_research_queue" ON public.nutrition_research_queue;
CREATE POLICY "anon_write_nutrition_research_queue" ON public.nutrition_research_queue
  FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "anon_update_nutrition_research_queue" ON public.nutrition_research_queue;
CREATE POLICY "anon_update_nutrition_research_queue" ON public.nutrition_research_queue
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_write_nutrition_research_queue" ON public.nutrition_research_queue;
CREATE POLICY "auth_write_nutrition_research_queue" ON public.nutrition_research_queue
  FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_nutrition_research_queue" ON public.nutrition_research_queue;
CREATE POLICY "auth_update_nutrition_research_queue" ON public.nutrition_research_queue
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);



-- -----------------------------------------------------------------------------
-- FROM: 20260401000000_security_linter_remediation_phase1.sql
-- -----------------------------------------------------------------------------
-- Phase 1 remediation for Supabase security linter findings.
-- Safe/idempotent fixes only:
-- 1) Ensure RLS is enabled on tables that already have policies.
-- 2) Fix mutable function search_path warnings for selected public functions.

-- ERROR fixes: policies exist but RLS disabled.
ALTER TABLE IF EXISTS public.checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.checklist_items ENABLE ROW LEVEL SECURITY;

-- WARN fixes: function_search_path_mutable.
-- We use dynamic ALTER FUNCTION by OID to avoid hardcoding signatures.
DO $$
DECLARE
  fn record;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS regproc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        '_auth_user_establishment_ids',
        'insert_iiko_products',
        'get_iiko_products',
        'delete_iiko_products',
        'check_establishment_access',
        'check_promo_code',
        'use_promo_code',
        'check_employee_limit',
        'check_parent_is_main'
      )
  LOOP
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path TO pg_catalog, public',
      fn.regproc
    );
  END LOOP;
END
$$;

-- WARN fix: extension_in_public.
-- Some managed extensions (including pg_net on Supabase) may not support SET SCHEMA.
-- Try to move, but do not fail migration if unsupported.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'pg_net'
      AND n.nspname = 'public'
  ) THEN
    CREATE SCHEMA IF NOT EXISTS extensions;
    BEGIN
      ALTER EXTENSION pg_net SET SCHEMA extensions;
    EXCEPTION
      WHEN feature_not_supported THEN
        RAISE NOTICE 'pg_net does not support SET SCHEMA on this instance; skipping.';
      WHEN object_not_in_prerequisite_state THEN
        RAISE NOTICE 'pg_net schema change is not allowed in current environment; skipping.';
    END;
  END IF;
END
$$;


-- -----------------------------------------------------------------------------
-- FROM: 20260401000100_establishment_inn_bin.sql
-- -----------------------------------------------------------------------------
-- Реквизиты заведения для бланка соглашения с сотрудником
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS inn_bin TEXT;
COMMENT ON COLUMN establishments.inn_bin IS 'ИНН или БИН для реквизитов (РФ/СНГ)';


-- -----------------------------------------------------------------------------
-- FROM: 20260401000200_tt_parse_learned_dish_name.sql
-- -----------------------------------------------------------------------------
-- Обучение: выученная позиция названия блюда (где искать при парсинге).
-- При правке пользователя ищем corrected в rows и сохраняем (row_offset, col).
CREATE TABLE IF NOT EXISTS tt_parse_learned_dish_name (
  header_signature text PRIMARY KEY,
  dish_name_row_offset int NOT NULL,
  dish_name_col int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE tt_parse_learned_dish_name IS 'Обучение: при правке пользователь указал откуда брать название. Общая таблица — один шаблон помогает всем заведениям (без establishment_id).';

ALTER TABLE tt_parse_learned_dish_name ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
CREATE POLICY "authenticated_select_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "authenticated_insert_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
CREATE POLICY "authenticated_insert_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_update_tt_parse_learned_dish" ON tt_parse_learned_dish_name;
CREATE POLICY "authenticated_update_tt_parse_learned_dish" ON tt_parse_learned_dish_name
  FOR UPDATE TO authenticated USING (true);


-- -----------------------------------------------------------------------------
-- FROM: 20260401000300_tech_card_custom_categories.sql
-- -----------------------------------------------------------------------------
-- Пользовательские категории ТТК (свой вариант) для кухни и бара.
-- Сохраняются для повторного использования. Удалить можно только если ни одна ТТК не использует категорию.
CREATE TABLE IF NOT EXISTS tech_card_custom_categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  department TEXT NOT NULL CHECK (department IN ('kitchen', 'bar')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tech_card_custom_categories_est_dept_name
  ON tech_card_custom_categories(establishment_id, department, LOWER(TRIM(name)));
CREATE INDEX IF NOT EXISTS idx_tech_card_custom_categories_establishment
  ON tech_card_custom_categories(establishment_id, department);

COMMENT ON TABLE tech_card_custom_categories IS 'Пользовательские категории ТТК. В tech_cards.category хранится custom:{id}. Удаление разрешено только при отсутствии ТТК с этой категорией.';

ALTER TABLE tech_card_custom_categories ENABLE ROW LEVEL SECURITY;

-- RLS: доступ только для своего заведения
DROP POLICY IF EXISTS "auth_select_tech_card_custom_categories" ON tech_card_custom_categories;
CREATE POLICY "auth_select_tech_card_custom_categories" ON tech_card_custom_categories
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid() OR auth_user_id = auth.uid())
  );

DROP POLICY IF EXISTS "auth_insert_tech_card_custom_categories" ON tech_card_custom_categories;
CREATE POLICY "auth_insert_tech_card_custom_categories" ON tech_card_custom_categories
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid() OR auth_user_id = auth.uid())
  );

DROP POLICY IF EXISTS "auth_delete_tech_card_custom_categories" ON tech_card_custom_categories;
CREATE POLICY "auth_delete_tech_card_custom_categories" ON tech_card_custom_categories
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid() OR auth_user_id = auth.uid())
  );


-- -----------------------------------------------------------------------------
-- FROM: 20260402010000_user_policy_consents.sql
-- -----------------------------------------------------------------------------
create table if not exists public.user_policy_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_type text not null default 'privacy_policy',
  policy_version text not null,
  accepted_at timestamptz not null default now(),
  locale text,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_policy_consents_unique unique (user_id, policy_type, policy_version)
);

alter table public.user_policy_consents enable row level security;

drop policy if exists user_policy_consents_select_own on public.user_policy_consents;
drop policy if exists user_policy_consents_insert_own on public.user_policy_consents;
drop policy if exists user_policy_consents_update_own on public.user_policy_consents;

create policy user_policy_consents_select_own
on public.user_policy_consents
for select
to authenticated
using (auth.uid() = user_id);

create policy user_policy_consents_insert_own
on public.user_policy_consents
for insert
to authenticated
with check (auth.uid() = user_id);

create policy user_policy_consents_update_own
on public.user_policy_consents
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.tg_user_policy_consents_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_policy_consents_updated_at on public.user_policy_consents;
create trigger trg_user_policy_consents_updated_at
before update on public.user_policy_consents
for each row
execute function public.tg_user_policy_consents_updated_at();


-- -----------------------------------------------------------------------------
-- FROM: 20260402120000_fix_current_user_establishment_ids_auth_user_id.sql
-- -----------------------------------------------------------------------------
-- Восстановить ветку employees.auth_user_id в current_user_establishment_ids / current_user_employee_ids.
-- Миграция 20260318100000 убрала её, предполагая что колонка удалена в 20260225180000; на реальных БД
-- auth_user_id по-прежнему используется (RPC создания сотрудников, политики в 20260401000300 и др.).
-- Если у сотрудника id <> auth.uid(), но auth_user_id = auth.uid(), без этой ветки RLS отклоняет
-- INSERT в establishment_haccp_config и другие tenant-таблицы (Postgrest 42501).

CREATE OR REPLACE FUNCTION public.current_user_establishment_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM establishments WHERE owner_id = auth.uid()
  UNION
  SELECT establishment_id FROM employees WHERE id = auth.uid()
  UNION
  SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_user_employee_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM employees WHERE id = auth.uid()
  UNION
  SELECT id FROM employees WHERE auth_user_id = auth.uid();
$$;


-- -----------------------------------------------------------------------------
-- FROM: 20260429120000_expenses_pro_enforcement.sql
-- -----------------------------------------------------------------------------
-- Раздел «Расходы» (Pro): серверная проверка подписки.
-- Клиент не может обойти через прямой SELECT — агрегирующие списки только через RPC ниже.

ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS subscription_type TEXT;

COMMENT ON COLUMN public.establishments.subscription_type IS 'free | pro | premium — доступ к Pro-функциям';

-- Проверка: пользователь состоит в заведении и у заведения подписка pro/premium.
CREATE OR REPLACE FUNCTION public.require_establishment_pro_for_expenses(p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'require_establishment_pro_for_expenses: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'require_establishment_pro_for_expenses: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.id = p_establishment_id
      AND COALESCE(lower(trim(e.subscription_type)), 'free') IN ('pro', 'premium')
  ) THEN
    RAISE EXCEPTION 'EXPENSES_PRO_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'subscription_type must be pro or premium';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.require_establishment_pro_for_expenses(uuid) IS
  'Вызывать перед загрузкой данных экрана «Расходы» / ФЗП; иначе исключение EXPENSES_PRO_REQUIRED.';

-- Список документов заказов продуктов для экрана «Расходы» (только Pro).
CREATE OR REPLACE FUNCTION public.list_order_documents_for_expenses(p_establishment_id uuid)
RETURNS SETOF public.order_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_establishment_pro_for_expenses(p_establishment_id);
  RETURN QUERY
  SELECT o.*
  FROM public.order_documents o
  WHERE o.establishment_id = p_establishment_id
  ORDER BY o.created_at DESC;
END;
$$;

-- Список документов инвентаризации/списаний для вкладки «Расходы» (только Pro).
CREATE OR REPLACE FUNCTION public.list_inventory_documents_for_expenses(p_establishment_id uuid)
RETURNS SETOF public.inventory_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_establishment_pro_for_expenses(p_establishment_id);
  RETURN QUERY
  SELECT d.*
  FROM public.inventory_documents d
  WHERE d.establishment_id = p_establishment_id
  ORDER BY d.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.require_establishment_pro_for_expenses(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.require_establishment_pro_for_expenses(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_order_documents_for_expenses(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_order_documents_for_expenses(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.list_inventory_documents_for_expenses(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_inventory_documents_for_expenses(uuid) TO authenticated;


-- -----------------------------------------------------------------------------
-- FROM: 20260429130000_promo_grants_pro_subscription.sql
-- -----------------------------------------------------------------------------
-- Промокод из админки = подписка Pro (establishments.subscription_type).
-- Ретроактивно для уже погашенных кодов и для всех новых регистраций по промокоду.

-- 1. Заведения с привязанным использованным промокодом получают Pro
UPDATE public.establishments e
SET subscription_type = 'pro',
    updated_at = now()
WHERE EXISTS (
  SELECT 1
  FROM public.promo_codes p
  WHERE p.used_by_establishment_id = e.id
    AND p.is_used = true
)
AND COALESCE(lower(trim(e.subscription_type)), 'free') NOT IN ('pro', 'premium');

-- 2. register_company_with_promo: сразу создаём заведение с Pro
CREATE OR REPLACE FUNCTION register_company_with_promo(
  p_code text,
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row promo_codes%rowtype;
  v_est_id uuid;
  v_est jsonb;
BEGIN
  SELECT * INTO v_row FROM promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF v_row.is_used THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  v_est_id := gen_random_uuid();
  INSERT INTO establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'pro',
    now(),
    now()
  );

  UPDATE promo_codes
  SET is_used = true, used_by_establishment_id = v_est_id, used_at = now()
  WHERE id = v_row.id;

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      created_at,
      updated_at
    FROM establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION register_company_with_promo(text, text, text, text) IS
  'Регистрация компании с промокодом; промокод из админки даёт подписку Pro.';


-- -----------------------------------------------------------------------------
-- FROM: 20260429140000_harden_product_alias_rejections_rls.sql
-- -----------------------------------------------------------------------------
-- Закрываем полный anon-доступ к product_alias_rejections (чтение/запись чужих заведений).
-- Приложение работает с Supabase Auth: authenticated + привязка к заведению пользователя.

ALTER TABLE public.product_alias_rejections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "anon_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_update_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_delete_product_alias_rejections" ON public.product_alias_rejections;

-- Глобальные строки (establishment_id IS NULL) — видны всем залогиненным (общий словарь отказов).
-- Строки заведения — только своё заведение.
CREATE POLICY "auth_select_product_alias_rejections"
ON public.product_alias_rejections
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_insert_product_alias_rejections"
ON public.product_alias_rejections
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_update_product_alias_rejections"
ON public.product_alias_rejections
FOR UPDATE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
)
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_delete_product_alias_rejections"
ON public.product_alias_rejections
FOR DELETE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);


-- -----------------------------------------------------------------------------
-- FROM: 20260429160000_security_hardening_industry_rls.sql
-- -----------------------------------------------------------------------------
-- =============================================================================
-- Industry-style RLS hardening (Phase 2): remove remaining anon broad access where
-- the app uses Supabase Auth; scope rows by tenant where applicable.
-- Does NOT touch: registration RPCs, pending_owner_registration anon INSERT,
-- platform_config, co_owner anon flows, find_establishment_by_pin, etc.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) product_aliases: remove anon SELECT; explicit auth SELECT by establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_product_aliases" ON public.product_aliases;
DROP POLICY IF EXISTS "auth_select_product_aliases" ON public.product_aliases;

CREATE POLICY "auth_select_product_aliases"
ON public.product_aliases
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

-- ---------------------------------------------------------------------------
-- 2) product_alias_rejections: idempotent final policies (stricter than early P0)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "anon_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_select_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_insert_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_update_product_alias_rejections" ON public.product_alias_rejections;
DROP POLICY IF EXISTS "auth_delete_product_alias_rejections" ON public.product_alias_rejections;

CREATE POLICY "auth_select_product_alias_rejections"
ON public.product_alias_rejections
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_insert_product_alias_rejections"
ON public.product_alias_rejections
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_update_product_alias_rejections"
ON public.product_alias_rejections
FOR UPDATE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
)
WITH CHECK (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "auth_delete_product_alias_rejections"
ON public.product_alias_rejections
FOR DELETE
TO authenticated
USING (
  establishment_id IS NOT NULL
  AND establishment_id IN (SELECT public.current_user_establishment_ids())
);

-- ---------------------------------------------------------------------------
-- 3) ai_ttk_daily_usage: Edge Functions use service_role (bypass RLS). Remove anon SELECT.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_ai_ttk_usage" ON public.ai_ttk_daily_usage;

DROP POLICY IF EXISTS "auth_select_ai_ttk_usage" ON public.ai_ttk_daily_usage;
CREATE POLICY "auth_select_ai_ttk_usage"
ON public.ai_ttk_daily_usage
FOR SELECT
TO authenticated
USING (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 4) iiko_blank_versions: authenticated + tenant only (Flutter uses Auth session)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_iiko_blank_versions_select" ON public.iiko_blank_versions;
DROP POLICY IF EXISTS "anon_iiko_blank_versions_insert" ON public.iiko_blank_versions;

DROP POLICY IF EXISTS "auth_iiko_blank_versions_select" ON public.iiko_blank_versions;
DROP POLICY IF EXISTS "auth_iiko_blank_versions_insert" ON public.iiko_blank_versions;
DROP POLICY IF EXISTS "auth_iiko_blank_versions_delete" ON public.iiko_blank_versions;

CREATE POLICY "auth_iiko_blank_versions_select"
ON public.iiko_blank_versions
FOR SELECT
TO authenticated
USING (establishment_id IN (SELECT public.current_user_establishment_ids()));

CREATE POLICY "auth_iiko_blank_versions_insert"
ON public.iiko_blank_versions
FOR INSERT
TO authenticated
WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

CREATE POLICY "auth_iiko_blank_versions_delete"
ON public.iiko_blank_versions
FOR DELETE
TO authenticated
USING (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 5) tt_parse_corrections: no anon; scope by establishment (NULL treated as global read for signed-in users)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_tt_parse_corrections" ON public.tt_parse_corrections;
DROP POLICY IF EXISTS "anon_insert_tt_parse_corrections" ON public.tt_parse_corrections;

DROP POLICY IF EXISTS "authenticated_select_tt_parse_corrections" ON public.tt_parse_corrections;
DROP POLICY IF EXISTS "authenticated_insert_tt_parse_corrections" ON public.tt_parse_corrections;

CREATE POLICY "authenticated_select_tt_parse_corrections"
ON public.tt_parse_corrections
FOR SELECT
TO authenticated
USING (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

CREATE POLICY "authenticated_insert_tt_parse_corrections"
ON public.tt_parse_corrections
FOR INSERT
TO authenticated
WITH CHECK (
  establishment_id IS NULL
  OR establishment_id IN (SELECT public.current_user_establishment_ids())
);

-- ---------------------------------------------------------------------------
-- 6) Nutrition layer: remove anon; keep global reads/writes for authenticated only.
--    Links/queue scoped via establishment_products (products has no establishment_id).
-- ---------------------------------------------------------------------------
-- nutrition_profiles
DROP POLICY IF EXISTS "anon_select_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "anon_write_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "anon_update_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_select_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_write_nutrition_profiles" ON public.nutrition_profiles;
DROP POLICY IF EXISTS "auth_update_nutrition_profiles" ON public.nutrition_profiles;

CREATE POLICY "auth_select_nutrition_profiles"
ON public.nutrition_profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth_write_nutrition_profiles"
ON public.nutrition_profiles FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "auth_update_nutrition_profiles"
ON public.nutrition_profiles FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- nutrition_aliases
DROP POLICY IF EXISTS "anon_select_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "anon_write_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "anon_update_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_select_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_write_nutrition_aliases" ON public.nutrition_aliases;
DROP POLICY IF EXISTS "auth_update_nutrition_aliases" ON public.nutrition_aliases;

CREATE POLICY "auth_select_nutrition_aliases"
ON public.nutrition_aliases FOR SELECT TO authenticated USING (true);

CREATE POLICY "auth_write_nutrition_aliases"
ON public.nutrition_aliases FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "auth_update_nutrition_aliases"
ON public.nutrition_aliases FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- product_nutrition_links
DROP POLICY IF EXISTS "anon_select_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "anon_write_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "anon_update_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_select_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_write_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_update_product_nutrition_links" ON public.product_nutrition_links;
DROP POLICY IF EXISTS "auth_delete_product_nutrition_links" ON public.product_nutrition_links;

CREATE POLICY "auth_select_product_nutrition_links"
ON public.product_nutrition_links
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_write_product_nutrition_links"
ON public.product_nutrition_links
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_update_product_nutrition_links"
ON public.product_nutrition_links
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_delete_product_nutrition_links"
ON public.product_nutrition_links
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = product_nutrition_links.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

-- nutrition_research_queue
DROP POLICY IF EXISTS "anon_select_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "anon_write_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "anon_update_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_select_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_write_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_update_nutrition_research_queue" ON public.nutrition_research_queue;
DROP POLICY IF EXISTS "auth_delete_nutrition_research_queue" ON public.nutrition_research_queue;

CREATE POLICY "auth_select_nutrition_research_queue"
ON public.nutrition_research_queue
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_write_nutrition_research_queue"
ON public.nutrition_research_queue
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_update_nutrition_research_queue"
ON public.nutrition_research_queue
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);

CREATE POLICY "auth_delete_nutrition_research_queue"
ON public.nutrition_research_queue
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.establishment_products ep
    WHERE ep.product_id = nutrition_research_queue.product_id
      AND ep.establishment_id IN (SELECT public.current_user_establishment_ids())
  )
);


-- -----------------------------------------------------------------------------
-- FROM: 20260430100000_security_hardening_phase3_pos_stock_errors_rls.sql
-- -----------------------------------------------------------------------------
-- Phase 3: POS / склад / журнал ошибок / заявки ТТК — убрать anon ALL, сузить authenticated по tenant.
-- Клиент Flutter ходит с JWT (authenticated). RPC SECURITY DEFINER и Edge (service_role) обходят RLS как задумано.
-- Опасные политики public+true на employees и allow_all на establishment_products — дроп при наличии.

-- ---------------------------------------------------------------------------
-- 0) Снять политики «всё всем», если остались от ручных правок / старых веток
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS allow_all_establishment_products ON public.establishment_products;

DROP POLICY IF EXISTS employees_select ON public.employees;
DROP POLICY IF EXISTS employees_insert ON public.employees;
DROP POLICY IF EXISTS employees_update ON public.employees;
DROP POLICY IF EXISTS employees_delete ON public.employees;

-- ---------------------------------------------------------------------------
-- 1) pos_dining_tables (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_dining_tables_all ON public.pos_dining_tables;
DROP POLICY IF EXISTS auth_pos_dining_tables_all ON public.pos_dining_tables;

CREATE POLICY auth_pos_dining_tables_all ON public.pos_dining_tables
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 2) pos_orders (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_orders_all ON public.pos_orders;
DROP POLICY IF EXISTS auth_pos_orders_all ON public.pos_orders;

CREATE POLICY auth_pos_orders_all ON public.pos_orders
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 3) pos_order_lines (через pos_orders)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_order_lines_all ON public.pos_order_lines;
DROP POLICY IF EXISTS auth_pos_order_lines_all ON public.pos_order_lines;

CREATE POLICY auth_pos_order_lines_all ON public.pos_order_lines
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_lines.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_lines.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

-- ---------------------------------------------------------------------------
-- 4) pos_order_payments (через pos_orders)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_order_payments_all ON public.pos_order_payments;
DROP POLICY IF EXISTS auth_pos_order_payments_all ON public.pos_order_payments;

CREATE POLICY auth_pos_order_payments_all ON public.pos_order_payments
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_payments.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.pos_orders o
      WHERE o.id = pos_order_payments.order_id
        AND o.establishment_id IN (SELECT public.current_user_establishment_ids())
    )
  );

-- ---------------------------------------------------------------------------
-- 5) pos_cash_shifts, pos_cash_disbursements (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_pos_cash_shifts_all ON public.pos_cash_shifts;
DROP POLICY IF EXISTS auth_pos_cash_shifts_all ON public.pos_cash_shifts;

CREATE POLICY auth_pos_cash_shifts_all ON public.pos_cash_shifts
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

DROP POLICY IF EXISTS anon_pos_cash_disbursements_all ON public.pos_cash_disbursements;
DROP POLICY IF EXISTS auth_pos_cash_disbursements_all ON public.pos_cash_disbursements;

CREATE POLICY auth_pos_cash_disbursements_all ON public.pos_cash_disbursements
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 6) establishment_stock_balances, establishment_stock_movements
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_establishment_stock_balances_all ON public.establishment_stock_balances;
DROP POLICY IF EXISTS auth_establishment_stock_balances_all ON public.establishment_stock_balances;

CREATE POLICY auth_establishment_stock_balances_all ON public.establishment_stock_balances
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

DROP POLICY IF EXISTS anon_establishment_stock_movements_all ON public.establishment_stock_movements;
DROP POLICY IF EXISTS auth_establishment_stock_movements_all ON public.establishment_stock_movements;

CREATE POLICY auth_establishment_stock_movements_all ON public.establishment_stock_movements
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 7) tech_card_change_requests (establishment_id)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_tech_card_change_requests_all ON public.tech_card_change_requests;
DROP POLICY IF EXISTS auth_tech_card_change_requests_all ON public.tech_card_change_requests;

CREATE POLICY auth_tech_card_change_requests_all ON public.tech_card_change_requests
  FOR ALL TO authenticated
  USING (establishment_id IN (SELECT public.current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT public.current_user_establishment_ids()));

-- ---------------------------------------------------------------------------
-- 8) system_errors — anon убрать; authenticated только по своему заведению
--    Вставка с Edge (service_role) по-прежнему без RLS.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS anon_system_errors_all ON public.system_errors;
DROP POLICY IF EXISTS auth_system_errors_all ON public.system_errors;

CREATE POLICY auth_system_errors_all ON public.system_errors
  FOR ALL TO authenticated
  USING (
    establishment_id IS NOT NULL
    AND establishment_id IN (SELECT public.current_user_establishment_ids())
  )
  WITH CHECK (
    establishment_id IS NOT NULL
    AND establishment_id IN (SELECT public.current_user_establishment_ids())
  );


-- -----------------------------------------------------------------------------
-- FROM: 20260430150000_register_company_without_promo.sql
-- -----------------------------------------------------------------------------
-- Регистрация компании без промокода: 72 ч доступа к Pro-функциям (pro_trial_ends_at), затем free.
-- Промокод из админки по-прежнему даёт постоянный Pro через register_company_with_promo.
--
-- ВАЖНО: выполняйте весь файл одним запуском (Supabase CLI, psql, «Run» без выделения куска).
-- Если в SQL Editor запускать по одной команде, разбитой по «;», тело PL/pgSQL внутри $$…$$
-- обрежется → ERROR 42601 syntax error at end of input (часто LINE 0).

-- subscription_type — из 20260429120000_expenses_pro_enforcement; на части БД миграция не накатывалась.
ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS subscription_type TEXT,
  ADD COLUMN IF NOT EXISTS pro_trial_ends_at TIMESTAMPTZ;

COMMENT ON COLUMN public.establishments.subscription_type IS 'free | pro | premium — доступ к Pro-функциям';

COMMENT ON COLUMN public.establishments.pro_trial_ends_at IS
  'До этой даты действует пробный Pro после регистрации без промокода (72 ч с момента создания).';

-- Серверные проверки Pro: подписка pro/premium ИЛИ активный пробный период.
CREATE OR REPLACE FUNCTION public.require_establishment_pro_for_expenses(p_establishment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'require_establishment_pro_for_expenses: not authenticated';
  END IF;

  IF NOT (p_establishment_id IN (SELECT public.current_user_establishment_ids())) THEN
    RAISE EXCEPTION 'require_establishment_pro_for_expenses: access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.id = p_establishment_id
      AND (
        COALESCE(lower(trim(e.subscription_type)), 'free') IN ('pro', 'premium')
        OR (e.pro_trial_ends_at IS NOT NULL AND e.pro_trial_ends_at > now())
      )
  ) THEN
    RAISE EXCEPTION 'EXPENSES_PRO_REQUIRED'
      USING ERRCODE = 'P0001',
            HINT = 'subscription_type must be pro/premium or pro_trial active';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.require_establishment_pro_for_expenses(uuid) IS
  'Pro для расходов: subscription pro/premium или активный pro_trial_ends_at.';

-- Регистрация без промокода (единственный безопасный путь наряду с register_company_with_promo).
CREATE OR REPLACE FUNCTION public.register_company_without_promo(
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_est_id uuid;
  v_est jsonb;
  v_trial_end timestamptz := now() + interval '72 hours';
BEGIN
  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    pro_trial_ends_at,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'free',
    v_trial_end,
    now(),
    now()
  );

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      pro_trial_ends_at,
      created_at,
      updated_at
    FROM public.establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_without_promo(text, text, text) IS
  'Регистрация компании без промокода; 72 ч Pro через pro_trial_ends_at, subscription_type = free.';

REVOKE ALL ON FUNCTION public.register_company_without_promo(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_company_without_promo(text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.register_company_without_promo(text, text, text) TO authenticated;

-- Возврат промокодной регистрации тоже отдаёт pro_trial_ends_at (обычно NULL).
CREATE OR REPLACE FUNCTION public.register_company_with_promo(
  p_code text,
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row promo_codes%rowtype;
  v_est_id uuid;
  v_est jsonb;
BEGIN
  SELECT * INTO v_row FROM public.promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF v_row.is_used THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    pro_trial_ends_at,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'pro',
    NULL,
    now(),
    now()
  );

  UPDATE public.promo_codes
  SET is_used = true, used_by_establishment_id = v_est_id, used_at = now()
  WHERE id = v_row.id;

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      pro_trial_ends_at,
      created_at,
      updated_at
    FROM public.establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_with_promo(text, text, text, text) IS
  'Регистрация с промокодом из админки; подписка Pro, без пробного окна.';


-- -----------------------------------------------------------------------------
-- FROM: 20260430160000_establishments_subscription_type_if_missing.sql
-- -----------------------------------------------------------------------------
-- Hotfix: на некоторых проектах не была применена 20260429120000_expenses_pro_enforcement.sql,
-- но register_company_* и клиент уже используют establishments.subscription_type.
ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS subscription_type TEXT;

COMMENT ON COLUMN public.establishments.subscription_type IS 'free | pro | premium — доступ к Pro-функциям';


-- -----------------------------------------------------------------------------
-- FROM: 20260430170000_pending_owner_registrations_updated_at.sql
-- -----------------------------------------------------------------------------
-- save_pending_owner_registration (20260324203000) INSERT ... created_at, updated_at,
-- но в 20260309300000 таблица создана только с created_at — без updated_at.
ALTER TABLE public.pending_owner_registrations
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

UPDATE public.pending_owner_registrations
SET updated_at = created_at
WHERE updated_at IS NULL;

ALTER TABLE public.pending_owner_registrations
  ALTER COLUMN updated_at SET DEFAULT now();

ALTER TABLE public.pending_owner_registrations
  ALTER COLUMN updated_at SET NOT NULL;

COMMENT ON COLUMN public.pending_owner_registrations.updated_at IS
  'Обновляется при UPSERT в save_pending_owner_registration.';


-- -----------------------------------------------------------------------------
-- FROM: 20260430180000_register_company_seed_default_pos_table.sql
-- -----------------------------------------------------------------------------
-- Дефолтный стол зала при регистрации компании: клиент до входа владельца идёт как anon,
-- RLS на pos_dining_tables только для authenticated — вызов из приложения давал 401.
-- Создаём строку внутри SECURITY DEFINER RPC (как задумано в phase3).

CREATE OR REPLACE FUNCTION public.register_company_without_promo(
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_est_id uuid;
  v_est jsonb;
  v_trial_end timestamptz := now() + interval '72 hours';
BEGIN
  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    pro_trial_ends_at,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'free',
    v_trial_end,
    now(),
    now()
  );

  INSERT INTO public.pos_dining_tables (
    establishment_id,
    floor_name,
    room_name,
    table_number,
    sort_order,
    status
  )
  VALUES (
    v_est_id,
    '1',
    'Основной',
    1,
    0,
    'free'
  );

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      pro_trial_ends_at,
      created_at,
      updated_at
    FROM public.establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_without_promo(text, text, text) IS
  'Регистрация компании без промокода; 72 ч Pro через pro_trial_ends_at; один стол зала по умолчанию.';

CREATE OR REPLACE FUNCTION public.register_company_with_promo(
  p_code text,
  p_name text,
  p_address text,
  p_pin_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row promo_codes%rowtype;
  v_est_id uuid;
  v_est jsonb;
BEGIN
  SELECT * INTO v_row FROM public.promo_codes
  WHERE upper(trim(code)) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROMO_INVALID';
  END IF;

  IF v_row.is_used THEN
    RAISE EXCEPTION 'PROMO_USED';
  END IF;

  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN
    RAISE EXCEPTION 'PROMO_NOT_STARTED';
  END IF;

  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'PROMO_EXPIRED';
  END IF;

  v_est_id := gen_random_uuid();
  INSERT INTO public.establishments (
    id,
    name,
    pin_code,
    address,
    default_currency,
    subscription_type,
    pro_trial_ends_at,
    created_at,
    updated_at
  )
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    'pro',
    NULL,
    now(),
    now()
  );

  INSERT INTO public.pos_dining_tables (
    establishment_id,
    floor_name,
    room_name,
    table_number,
    sort_order,
    status
  )
  VALUES (
    v_est_id,
    '1',
    'Основной',
    1,
    0,
    'free'
  );

  UPDATE public.promo_codes
  SET is_used = true, used_by_establishment_id = v_est_id, used_at = now()
  WHERE id = v_row.id;

  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT
      id,
      name,
      pin_code,
      owner_id,
      address,
      phone,
      email,
      default_currency,
      subscription_type,
      pro_trial_ends_at,
      created_at,
      updated_at
    FROM public.establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.register_company_with_promo(text, text, text, text) IS
  'Регистрация с промокодом; один стол зала по умолчанию.';

