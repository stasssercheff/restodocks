-- =============================================================================
-- RESTODOCKS BETA — полная схема БД (часть 1: таблицы + политики + функции)
-- Выполнить ПЕРВЫМ в Supabase SQL Editor (Restodocks_beta)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ШАГ 1: Базовые таблицы
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS establishments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  pin_code TEXT NOT NULL UNIQUE,
  owner_id UUID,
  address TEXT,
  phone TEXT,
  email TEXT,
  default_currency TEXT DEFAULT 'RUB',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS employees (
  id UUID PRIMARY KEY,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT,
  department TEXT NOT NULL,
  section TEXT,
  roles TEXT[] NOT NULL DEFAULT '{}',
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  personal_pin TEXT,
  preferred_language TEXT DEFAULT 'ru',
  is_active BOOLEAN DEFAULT true,
  data_access_enabled BOOLEAN DEFAULT false NOT NULL,
  surname TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT fk_employees_auth FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS products (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL,
  names JSONB,
  calories REAL,
  protein REAL,
  fat REAL,
  carbs REAL,
  contains_gluten BOOLEAN,
  contains_lactose BOOLEAN,
  base_price REAL,
  currency TEXT,
  unit TEXT,
  supplier_ids UUID[] DEFAULT '{}',
  package_size REAL,
  package_unit TEXT,
  package_price REAL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS cooking_processes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  localized_names JSONB,
  calorie_multiplier REAL NOT NULL DEFAULT 1.0,
  protein_multiplier REAL NOT NULL DEFAULT 1.0,
  fat_multiplier REAL NOT NULL DEFAULT 1.0,
  carbs_multiplier REAL NOT NULL DEFAULT 1.0,
  weight_loss_percentage REAL NOT NULL DEFAULT 0.0,
  applicable_categories TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tech_cards (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  dish_name TEXT NOT NULL,
  dish_name_localized JSONB,
  category TEXT NOT NULL,
  portion_weight REAL NOT NULL DEFAULT 100.0,
  yield REAL NOT NULL DEFAULT 0.0,
  technology TEXT DEFAULT '',
  comment TEXT DEFAULT '',
  card_type TEXT NOT NULL DEFAULT 'dish',
  base_portions INT NOT NULL DEFAULT 1,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by UUID NOT NULL,
  photo_urls JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS tt_ingredients (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id UUID REFERENCES products(id),
  product_name TEXT NOT NULL,
  cooking_process_id UUID REFERENCES cooking_processes(id),
  cooking_process_name TEXT,
  gross_weight REAL NOT NULL,
  net_weight REAL NOT NULL,
  is_net_weight_manual BOOLEAN DEFAULT false,
  final_calories REAL NOT NULL DEFAULT 0,
  final_protein REAL NOT NULL DEFAULT 0,
  final_fat REAL NOT NULL DEFAULT 0,
  final_carbs REAL NOT NULL DEFAULT 0,
  cost REAL NOT NULL DEFAULT 0,
  tech_card_id UUID NOT NULL REFERENCES tech_cards(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS establishment_products (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  price REAL,
  currency TEXT,
  UNIQUE(establishment_id, product_id)
);
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '1 hour'),
  used_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS co_owner_invitations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  invited_email TEXT NOT NULL,
  invited_by UUID NOT NULL REFERENCES employees(id),
  invitation_token TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired')),
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '7 days'),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE co_owner_invitations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS product_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  old_price REAL,
  new_price REAL NOT NULL,
  currency TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE product_price_history ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS inventory_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);
ALTER TABLE inventory_drafts ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS establishment_schedule_data (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);
ALTER TABLE establishment_schedule_data ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS establishment_order_list_data (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '[]',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);
ALTER TABLE establishment_order_list_data ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS inventory_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_email TEXT NOT NULL,
  payload JSONB NOT NULL,
  email_sent_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE inventory_documents ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS order_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_chef_id UUID REFERENCES employees(id) ON DELETE CASCADE,
  recipient_email TEXT,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE order_documents ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS checklists (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  additional_name TEXT,
  type TEXT DEFAULT 'tasks',
  action_config JSONB DEFAULT '{"has_numeric":false,"has_toggle":true}'::jsonb,
  assigned_section TEXT,
  assigned_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS checklist_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  target_quantity REAL,
  tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS checklist_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(checklist_id, employee_id)
);
ALTER TABLE checklist_drafts ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS checklist_submissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  checklist_id UUID NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
  checklist_name TEXT DEFAULT '',
  submitted_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  recipient_chef_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  payload JSONB NOT NULL,
  section TEXT,
  filled_by TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS translation_cache (
  id bigserial primary key,
  source_text text NOT NULL,
  source_lang text NOT NULL DEFAULT 'ru',
  target_lang text NOT NULL DEFAULT 'en',
  translated text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT translation_cache_unique UNIQUE (source_text, source_lang, target_lang)
);
ALTER TABLE translation_cache ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS translations (
  id bigserial primary key,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  field_name text NOT NULL,
  source_text text NOT NULL,
  source_language text NOT NULL DEFAULT 'ru',
  target_language text NOT NULL,
  translated_text text NOT NULL,
  is_manual_override boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by text,
  CONSTRAINT translations_unique UNIQUE (entity_type, entity_id, field_name, source_language, target_language)
);
ALTER TABLE translations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS promo_codes (
  id bigserial primary key,
  code text NOT NULL UNIQUE,
  is_used boolean NOT NULL DEFAULT false,
  used_by_establishment_id uuid REFERENCES establishments(id) ON DELETE SET NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  note text,
  expires_at timestamptz,
  starts_at timestamptz,
  max_employees integer
);
ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- ШАГ 2: Индексы
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_employees_establishment ON employees(establishment_id);
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_establishment_id ON co_owner_invitations(establishment_id);
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_invitation_token ON co_owner_invitations(invitation_token);
CREATE INDEX IF NOT EXISTS idx_product_price_history_est_prod ON product_price_history(establishment_id, product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_establishment ON inventory_drafts(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_documents_establishment ON inventory_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_documents_recipient ON inventory_documents(recipient_chef_id);
CREATE INDEX IF NOT EXISTS idx_order_documents_establishment ON order_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_order_documents_recipient ON order_documents(recipient_chef_id) WHERE recipient_chef_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_checklists_establishment ON checklists(establishment_id);
CREATE INDEX IF NOT EXISTS idx_checklist_items_checklist ON checklist_items(checklist_id);
CREATE INDEX IF NOT EXISTS idx_checklist_drafts_checklist ON checklist_drafts(checklist_id);
CREATE INDEX IF NOT EXISTS idx_checklist_submissions_establishment ON checklist_submissions(establishment_id);
CREATE INDEX IF NOT EXISTS translation_cache_lookup ON translation_cache(source_lang, target_lang, source_text);
CREATE INDEX IF NOT EXISTS translations_entity_idx ON translations(entity_type, entity_id, field_name);

-- ---------------------------------------------------------------------------
-- ШАГ 3: RLS политики
-- ---------------------------------------------------------------------------

-- establishments
DROP POLICY IF EXISTS "anon_select_establishments" ON establishments;
CREATE POLICY "anon_select_establishments" ON establishments FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
CREATE POLICY "auth_select_establishments" ON establishments FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
CREATE POLICY "auth_update_establishments" ON establishments FOR UPDATE TO authenticated
  USING (owner_id = auth.uid() OR id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())) WITH CHECK (true);

-- employees
DROP POLICY IF EXISTS "anon_select_employees" ON employees;
CREATE POLICY "anon_select_employees" ON employees FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
CREATE POLICY "auth_select_employees" ON employees FOR SELECT TO authenticated
  USING (id = auth.uid() OR establishment_id IN (SELECT establishment_id FROM employees e2 WHERE e2.id = auth.uid()));
DROP POLICY IF EXISTS "auth_insert_employees" ON employees;
CREATE POLICY "auth_insert_employees" ON employees FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
DROP POLICY IF EXISTS "auth_update_employees" ON employees;
CREATE POLICY "auth_update_employees" ON employees FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (true);

-- products (global catalog)
DROP POLICY IF EXISTS "auth_select_products" ON products;
CREATE POLICY "auth_select_products" ON products FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "auth_insert_products" ON products;
CREATE POLICY "auth_insert_products" ON products FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "auth_update_products" ON products;
CREATE POLICY "auth_update_products" ON products FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_delete_products" ON products;
CREATE POLICY "auth_delete_products" ON products FOR DELETE TO authenticated USING (true);

-- establishment_products
DROP POLICY IF EXISTS "auth_select_establishment_products" ON establishment_products;
CREATE POLICY "auth_select_establishment_products" ON establishment_products FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_insert_establishment_products" ON establishment_products;
CREATE POLICY "auth_insert_establishment_products" ON establishment_products FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_update_establishment_products" ON establishment_products;
CREATE POLICY "auth_update_establishment_products" ON establishment_products FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()))
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_delete_establishment_products" ON establishment_products;
CREATE POLICY "auth_delete_establishment_products" ON establishment_products FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- co_owner_invitations
DROP POLICY IF EXISTS "anon_select_co_owner_invitations" ON co_owner_invitations;
CREATE POLICY "anon_select_co_owner_invitations" ON co_owner_invitations FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;
CREATE POLICY "anon_update_co_owner_invitations" ON co_owner_invitations FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can view co-owner invitations" ON co_owner_invitations FOR SELECT
  USING (establishment_id IN (SELECT e.id FROM establishments e JOIN employees emp ON emp.establishment_id = e.id WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)));
DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can create co-owner invitations" ON co_owner_invitations FOR INSERT
  WITH CHECK (establishment_id IN (SELECT e.id FROM establishments e JOIN employees emp ON emp.establishment_id = e.id WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)));
DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can update co-owner invitations" ON co_owner_invitations FOR UPDATE
  USING (establishment_id IN (SELECT e.id FROM establishments e JOIN employees emp ON emp.establishment_id = e.id WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)));

-- product_price_history
DROP POLICY IF EXISTS "auth_select_product_price_history" ON product_price_history;
CREATE POLICY "auth_select_product_price_history" ON product_price_history FOR SELECT
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_insert_product_price_history" ON product_price_history;
CREATE POLICY "auth_insert_product_price_history" ON product_price_history FOR INSERT
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- inventory_drafts
DROP POLICY IF EXISTS "auth_inventory_drafts" ON inventory_drafts;
CREATE POLICY "auth_inventory_drafts" ON inventory_drafts FOR ALL TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()))
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- inventory_documents
DROP POLICY IF EXISTS "auth_inventory_documents_select" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_select" ON inventory_documents FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()) OR recipient_chef_id = auth.uid());
DROP POLICY IF EXISTS "auth_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_insert" ON inventory_documents FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- order_documents
DROP POLICY IF EXISTS "auth_order_documents_select" ON order_documents;
CREATE POLICY "auth_order_documents_select" ON order_documents FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_order_documents_insert" ON order_documents;
CREATE POLICY "auth_order_documents_insert" ON order_documents FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- establishment_schedule_data
DROP POLICY IF EXISTS "auth_schedule_select" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_select" ON establishment_schedule_data FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_schedule_insert" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_insert" ON establishment_schedule_data FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_schedule_update" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_update" ON establishment_schedule_data FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()))
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- establishment_order_list_data
DROP POLICY IF EXISTS "auth_order_list_select" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_select" ON establishment_order_list_data FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_order_list_insert" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_insert" ON establishment_order_list_data FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_order_list_update" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_update" ON establishment_order_list_data FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()))
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- tech_cards
DROP POLICY IF EXISTS "auth_select_tech_cards" ON tech_cards;
CREATE POLICY "auth_select_tech_cards" ON tech_cards FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_insert_tech_cards" ON tech_cards;
CREATE POLICY "auth_insert_tech_cards" ON tech_cards FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_update_tech_cards" ON tech_cards;
CREATE POLICY "auth_update_tech_cards" ON tech_cards FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()))
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));
DROP POLICY IF EXISTS "auth_delete_tech_cards" ON tech_cards;
CREATE POLICY "auth_delete_tech_cards" ON tech_cards FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- checklists
DROP POLICY IF EXISTS "anon_checklists_all" ON checklists;
CREATE POLICY "anon_checklists_all" ON checklists FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_checklists_all" ON checklists;
CREATE POLICY "auth_checklists_all" ON checklists FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- checklist_items
DROP POLICY IF EXISTS "anon_checklist_items_all" ON checklist_items;
CREATE POLICY "anon_checklist_items_all" ON checklist_items FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "auth_checklist_items_all" ON checklist_items;
CREATE POLICY "auth_checklist_items_all" ON checklist_items FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- checklist_drafts
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
CREATE POLICY "auth_checklist_drafts_all" ON checklist_drafts FOR ALL TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()))
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- checklist_submissions
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;
CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions FOR ALL TO authenticated
  USING (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()) OR recipient_chef_id = auth.uid())
  WITH CHECK (establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid()));

-- translation_cache
DROP POLICY IF EXISTS "service_role full access" ON translation_cache;
CREATE POLICY "service_role full access" ON translation_cache FOR ALL TO service_role USING (true) WITH CHECK (true);

-- translations
DROP POLICY IF EXISTS "translations_select" ON translations;
CREATE POLICY "translations_select" ON translations FOR SELECT USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "translations_insert" ON translations;
CREATE POLICY "translations_insert" ON translations FOR INSERT WITH CHECK (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "translations_update" ON translations;
CREATE POLICY "translations_update" ON translations FOR UPDATE USING (auth.role() = 'authenticated');

-- promo_codes
DROP POLICY IF EXISTS "service_role full access" ON promo_codes;
CREATE POLICY "service_role full access" ON promo_codes FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- ШАГ 4: Storage RLS
-- ---------------------------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='avatars_insert_authenticated') THEN
    CREATE POLICY "avatars_insert_authenticated" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'avatars');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='avatars_update_authenticated') THEN
    CREATE POLICY "avatars_update_authenticated" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'avatars') WITH CHECK (bucket_id = 'avatars');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='avatars_select_public') THEN
    CREATE POLICY "avatars_select_public" ON storage.objects FOR SELECT TO public USING (bucket_id = 'avatars');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='avatars_delete_authenticated') THEN
    CREATE POLICY "avatars_delete_authenticated" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'avatars');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='tech_card_photos_insert_authenticated') THEN
    CREATE POLICY "tech_card_photos_insert_authenticated" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'tech_card_photos');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='tech_card_photos_update_authenticated') THEN
    CREATE POLICY "tech_card_photos_update_authenticated" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'tech_card_photos') WITH CHECK (bucket_id = 'tech_card_photos');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='tech_card_photos_select_public') THEN
    CREATE POLICY "tech_card_photos_select_public" ON storage.objects FOR SELECT TO public USING (bucket_id = 'tech_card_photos');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='tech_card_photos_delete_authenticated') THEN
    CREATE POLICY "tech_card_photos_delete_authenticated" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'tech_card_photos');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- ШАГ 5: Functions (RPCs)
-- ---------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION check_promo_code(p_code text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_row promo_codes%rowtype;
BEGIN
  SELECT * INTO v_row FROM promo_codes WHERE upper(trim(code)) = upper(trim(p_code));
  IF NOT FOUND THEN RETURN 'invalid'; END IF;
  IF v_row.is_used THEN RETURN 'used'; END IF;
  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN RETURN 'not_started'; END IF;
  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN RETURN 'expired'; END IF;
  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION use_promo_code(p_code text, p_establishment_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_row promo_codes%rowtype;
BEGIN
  SELECT * INTO v_row FROM promo_codes WHERE upper(trim(code)) = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RETURN 'invalid'; END IF;
  IF v_row.is_used THEN RETURN 'used'; END IF;
  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN RETURN 'not_started'; END IF;
  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN RETURN 'expired'; END IF;
  UPDATE promo_codes SET is_used=true, used_by_establishment_id=p_establishment_id, used_at=now() WHERE id=v_row.id;
  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION check_establishment_access(p_establishment_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_row promo_codes%rowtype;
BEGIN
  SELECT * INTO v_row FROM promo_codes WHERE used_by_establishment_id = p_establishment_id LIMIT 1;
  IF NOT FOUND THEN RETURN 'ok'; END IF;
  IF v_row.starts_at IS NOT NULL AND v_row.starts_at > now() THEN RETURN 'not_started'; END IF;
  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN RETURN 'expired'; END IF;
  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION check_employee_limit(p_establishment_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_max integer; v_count integer;
BEGIN
  SELECT max_employees INTO v_max FROM promo_codes WHERE used_by_establishment_id = p_establishment_id LIMIT 1;
  IF NOT FOUND OR v_max IS NULL THEN RETURN 'ok'; END IF;
  SELECT count(*) INTO v_count FROM employees WHERE establishment_id = p_establishment_id AND is_active = true;
  IF v_count >= v_max THEN RETURN 'limit_reached'; END IF;
  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION public.create_owner_employee(
  p_auth_user_id uuid, p_establishment_id uuid, p_full_name text,
  p_surname text, p_email text, p_roles text[] DEFAULT ARRAY['owner']
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_exists boolean; v_emp jsonb; v_personal_pin text; v_now timestamptz := now();
BEGIN
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user_id AND LOWER(email)=LOWER(trim(p_email))) INTO v_exists;
  IF NOT v_exists THEN RAISE EXCEPTION 'auth user not found or email mismatch'; END IF;
  IF NOT EXISTS(SELECT 1 FROM establishments WHERE id=p_establishment_id) THEN RAISE EXCEPTION 'establishment not found'; END IF;
  v_personal_pin := lpad((floor(random()*900000)+100000)::text,6,'0');
  INSERT INTO employees(id,full_name,surname,email,password_hash,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,data_access_enabled,created_at,updated_at)
  VALUES(p_auth_user_id,trim(p_full_name),nullif(trim(p_surname),''),trim(p_email),NULL,'management',NULL,p_roles,p_establishment_id,v_personal_pin,'ru',true,true,v_now,v_now);
  UPDATE establishments SET owner_id=p_auth_user_id, updated_at=v_now WHERE id=p_establishment_id;
  SELECT to_jsonb(r) INTO v_emp FROM(SELECT id,full_name,surname,email,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,data_access_enabled,created_at,updated_at FROM employees WHERE id=p_auth_user_id)r;
  RETURN v_emp;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_owner_employee TO anon;
GRANT EXECUTE ON FUNCTION public.create_owner_employee TO authenticated;

CREATE OR REPLACE FUNCTION public.create_employee_self_register(
  p_auth_user_id uuid, p_establishment_id uuid, p_full_name text,
  p_surname text, p_email text, p_department text, p_section text, p_roles text[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_auth_exists boolean; v_personal_pin text; v_now timestamptz := now(); v_emp jsonb;
BEGIN
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user_id AND LOWER(email)=LOWER(trim(p_email))) INTO v_auth_exists;
  IF NOT v_auth_exists THEN RAISE EXCEPTION 'auth user not found or email mismatch'; END IF;
  IF NOT EXISTS(SELECT 1 FROM establishments WHERE id=p_establishment_id) THEN RAISE EXCEPTION 'establishment not found'; END IF;
  IF EXISTS(SELECT 1 FROM employees WHERE establishment_id=p_establishment_id AND LOWER(email)=LOWER(trim(p_email))) THEN RAISE EXCEPTION 'email already taken'; END IF;
  v_personal_pin := lpad((floor(random()*900000)+100000)::text,6,'0');
  INSERT INTO employees(id,full_name,surname,email,password_hash,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,data_access_enabled,created_at,updated_at)
  VALUES(p_auth_user_id,trim(p_full_name),nullif(trim(p_surname),''),trim(p_email),NULL,COALESCE(NULLIF(trim(p_department),''),'kitchen'),nullif(trim(p_section),''),p_roles,p_establishment_id,v_personal_pin,'ru',true,false,v_now,v_now);
  SELECT to_jsonb(r) INTO v_emp FROM(SELECT id,full_name,surname,email,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,data_access_enabled,created_at,updated_at FROM employees WHERE id=p_auth_user_id)r;
  RETURN v_emp;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_employee_self_register TO anon;
GRANT EXECUTE ON FUNCTION public.create_employee_self_register TO authenticated;

CREATE OR REPLACE FUNCTION public.create_employee_for_company(
  p_auth_user_id uuid, p_establishment_id uuid, p_full_name text,
  p_surname text, p_email text, p_department text, p_section text, p_roles text[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller_id uuid; v_is_owner boolean; v_auth_exists boolean; v_personal_pin text; v_now timestamptz := now(); v_emp jsonb;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'must be authenticated'; END IF;
  SELECT EXISTS(SELECT 1 FROM employees e WHERE e.id=v_caller_id AND e.establishment_id=p_establishment_id AND 'owner'=ANY(e.roles) AND e.is_active=true) INTO v_is_owner;
  IF NOT v_is_owner THEN RAISE EXCEPTION 'only owner can add employees'; END IF;
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id=p_auth_user_id AND LOWER(email)=LOWER(trim(p_email))) INTO v_auth_exists;
  IF NOT v_auth_exists THEN RAISE EXCEPTION 'auth user not found or email mismatch'; END IF;
  IF NOT EXISTS(SELECT 1 FROM establishments WHERE id=p_establishment_id) THEN RAISE EXCEPTION 'establishment not found'; END IF;
  IF EXISTS(SELECT 1 FROM employees WHERE establishment_id=p_establishment_id AND LOWER(email)=LOWER(trim(p_email))) THEN RAISE EXCEPTION 'email already taken in establishment'; END IF;
  v_personal_pin := lpad((floor(random()*900000)+100000)::text,6,'0');
  INSERT INTO employees(id,full_name,surname,email,password_hash,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,data_access_enabled,created_at,updated_at)
  VALUES(p_auth_user_id,trim(p_full_name),nullif(trim(p_surname),''),trim(p_email),NULL,COALESCE(NULLIF(trim(p_department),''),'kitchen'),nullif(trim(p_section),''),p_roles,p_establishment_id,v_personal_pin,'ru',true,false,v_now,v_now);
  SELECT to_jsonb(r) INTO v_emp FROM(SELECT id,full_name,surname,email,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,data_access_enabled,created_at,updated_at FROM employees WHERE id=p_auth_user_id)r;
  RETURN v_emp;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_employee_for_company TO authenticated;

CREATE OR REPLACE FUNCTION public.fix_owner_without_employee(p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_auth_id uuid; v_est_id uuid; v_name text; v_emp jsonb; v_personal_pin text; v_now timestamptz := now();
BEGIN
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN RAISE EXCEPTION 'must be authenticated'; END IF;
  IF LOWER(trim(p_email)) != (SELECT LOWER(email) FROM auth.users WHERE id=v_auth_id) THEN RAISE EXCEPTION 'email does not match'; END IF;
  IF EXISTS(SELECT 1 FROM employees WHERE id=v_auth_id) THEN
    SELECT to_jsonb(r) INTO v_emp FROM(SELECT id,full_name,surname,email,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,created_at,updated_at FROM employees WHERE id=v_auth_id)r;
    RETURN v_emp;
  END IF;
  SELECT id INTO v_est_id FROM establishments WHERE owner_id=v_auth_id LIMIT 1;
  IF v_est_id IS NULL THEN SELECT id INTO v_est_id FROM establishments WHERE owner_id IS NULL ORDER BY created_at DESC LIMIT 1; END IF;
  IF v_est_id IS NULL THEN RAISE EXCEPTION 'no establishment for this owner'; END IF;
  v_name := COALESCE((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id=v_auth_id), split_part(trim(p_email),'@',1));
  v_personal_pin := lpad((floor(random()*900000)+100000)::text,6,'0');
  INSERT INTO employees(id,full_name,surname,email,password_hash,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,created_at,updated_at)
  VALUES(v_auth_id,v_name,NULL,trim(p_email),NULL,'management',NULL,ARRAY['owner'],v_est_id,v_personal_pin,'ru',true,v_now,v_now);
  UPDATE establishments SET owner_id=v_auth_id, updated_at=v_now WHERE id=v_est_id AND (owner_id IS NULL OR owner_id=v_auth_id);
  SELECT to_jsonb(r) INTO v_emp FROM(SELECT id,full_name,surname,email,department,section,roles,establishment_id,personal_pin,preferred_language,is_active,created_at,updated_at FROM employees WHERE id=v_auth_id)r;
  RETURN v_emp;
END;
$$;
GRANT EXECUTE ON FUNCTION public.fix_owner_without_employee TO authenticated;
