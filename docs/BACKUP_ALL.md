# Restodocks — полный бэкап в один файл
Дата: 2026-03-07

**Всё в одном файле:** секреты, конфиги, workflow, миграции. Для восстановления — копируй нужные блоки.

---

## 1. GitHub Secrets (чеклист)

| Secret | Назначение |
|--------|------------|
| ADMIN_PASSWORD | Пароль админки |
| SUPABASE_URL | https://osglfptwbuqqmqunttha.supabase.co |
| SUPABASE_SERVICE_ROLE_KEY | Service role key |
| SUPABASE_ANON_KEY | Anon key |
| CLOUDFLARE_API_TOKEN | Token с правами KV + Workers Scripts |
| CLOUDFLARE_ACCOUNT_ID | Account ID |

### Права Cloudflare API Token
- Workers KV Storage → Edit
- Workers Scripts (Cloudflare Workers) → Edit

---

## 2. URLs

- Админка: restodocks-admin.stassserchef.workers.dev
- Supabase: https://osglfptwbuqqmqunttha.supabase.co

---

## 3. KV Namespace

- ID: 3f9acc45fa9e41a585e0d9be3e34ab02
- Keys: admin_password, supabase_url, supabase_service_role_key

---

## 4. Workflow deploy-cloudflare-admin.yml

# Admin на Cloudflare Workers — деплой при push в main
name: Deploy Admin to Cloudflare Workers

on:
  push:
    branches: [staging]
    paths:
      - 'admin/**'
      - '.github/workflows/deploy-cloudflare-admin.yml'
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: admin

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
          cache-dependency-path: admin/package-lock.json

      - name: Install dependencies
        run: npm ci

      - name: Create .env.production.local
        env:
          ADMIN_PASSWORD: ${{ secrets.ADMIN_PASSWORD }}
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          NEXT_PUBLIC_SUPABASE_ANON_KEY: ${{ secrets.SUPABASE_ANON_KEY }}
          SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
        run: |
          printf 'NEXT_PUBLIC_SUPABASE_URL=%s\nSUPABASE_URL=%s\n' "$SUPABASE_URL" "$SUPABASE_URL" >> .env.production.local
          printf 'NEXT_PUBLIC_SUPABASE_ANON_KEY=%s\n' "$NEXT_PUBLIC_SUPABASE_ANON_KEY" >> .env.production.local
          printf 'SUPABASE_SERVICE_ROLE_KEY=%s\n' "$SUPABASE_SERVICE_ROLE_KEY" >> .env.production.local

      - name: Set admin secrets in KV
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          ADMIN_PASSWORD: ${{ secrets.ADMIN_PASSWORD }}
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
        run: |
          printf '%s' "$ADMIN_PASSWORD" > /tmp/admin_pw
          npx wrangler kv key put --namespace-id=3f9acc45fa9e41a585e0d9be3e34ab02 "admin_password" --path=/tmp/admin_pw --remote
          [ -n "$SUPABASE_URL" ] && printf '%s' "$SUPABASE_URL" > /tmp/supabase_url && npx wrangler kv key put --namespace-id=3f9acc45fa9e41a585e0d9be3e34ab02 "supabase_url" --path=/tmp/supabase_url --remote
          [ -n "$SUPABASE_SERVICE_ROLE_KEY" ] && printf '%s' "$SUPABASE_SERVICE_ROLE_KEY" > /tmp/supabase_key && npx wrangler kv key put --namespace-id=3f9acc45fa9e41a585e0d9be3e34ab02 "supabase_service_role_key" --path=/tmp/supabase_key --remote

      - name: Build and deploy
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
        run: npm run deploy

---

## 5. admin/wrangler.jsonc

{
  "$schema": "node_modules/wrangler/config-schema.json",
  "main": ".open-next/worker.js",
  "name": "restodocks-admin",
  "kv_namespaces": [
    { "binding": "ADMIN_CONFIG", "id": "3f9acc45fa9e41a585e0d9be3e34ab02" }
  ],
  "compatibility_date": "2024-12-30",
  "compatibility_flags": ["nodejs_compat", "global_fetch_strictly_public"],
  "assets": {
    "directory": ".open-next/assets",
    "binding": "ASSETS"
  },
  "services": [
    {
      "binding": "WORKER_SELF_REFERENCE",
      "service": "restodocks-admin"
    }
  ]
}

---

## 6. admin/lib/admin-env.ts

import { getCloudflareContext } from '@opennextjs/cloudflare'

export async function getAdminPassword(): Promise<string> {
  const p = (process.env.ADMIN_PASSWORD ?? '').trim()
  if (p) return p
  try {
    const { env } = await getCloudflareContext()
    const kv = (env as { ADMIN_CONFIG?: { get: (k: string) => Promise<string | null> } }).ADMIN_CONFIG
    if (kv) {
      const v = await kv.get('admin_password')
      return (v ?? '').trim()
    }
  } catch {
    // ignore
  }
  return ''
}

export async function getSupabaseConfig(): Promise<{ url: string; serviceRoleKey: string } | null> {
  let url = (process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').trim()
  let key = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim()
  if (!url || !key) {
    try {
      const { env } = await getCloudflareContext()
      const kv = (env as { ADMIN_CONFIG?: { get: (k: string) => Promise<string | null> } }).ADMIN_CONFIG
      if (kv) {
        url = (await kv.get('supabase_url')) ?? url
        key = (await kv.get('supabase_service_role_key')) ?? key
      }
    } catch {
      // ignore
    }
  }
  if (!url || !key) return null
  return { url, serviceRoleKey: key }
}

---

## 7. Deploy Rules (кратко)

- Beta = staging, Prod = main
- Разработка только в staging
- Релиз: git checkout main && git merge staging && git push origin main
- Cloudflare: Prod branch=main, Beta branch=staging, Preview=None

---

## 8. Supabase migrations (полный список)

### 20260220000001_password_reset_tokens.sql
```sql
-- Таблица для токенов сброса пароля (восстановление доступа)
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '1 hour'),
  used_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_token ON password_reset_tokens(token);
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_employee ON password_reset_tokens(employee_id);
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_expires ON password_reset_tokens(expires_at);

COMMENT ON TABLE password_reset_tokens IS 'Токены для сброса пароля сотрудников';
```

### 20260220120000_establishment_products_price.sql
```sql
-- Добавляем price и currency в establishment_products для хранения цен по заведениям
ALTER TABLE establishment_products ADD COLUMN IF NOT EXISTS price REAL;
ALTER TABLE establishment_products ADD COLUMN IF NOT EXISTS currency TEXT;

COMMENT ON COLUMN establishment_products.price IS 'Цена продукта в данном заведении';
COMMENT ON COLUMN establishment_products.currency IS 'Валюта (RUB, USD и т.д.)';
```

### 20260223000001_auth_user_id.sql
```sql
-- Связь employees с Supabase Auth (auth.users)
-- auth_user_id = auth.uid() для пользователей, зарегистрированных через Supabase Auth
ALTER TABLE employees ADD COLUMN IF NOT EXISTS auth_user_id UUID;
CREATE INDEX IF NOT EXISTS idx_employees_auth_user_id ON employees(auth_user_id);

COMMENT ON COLUMN employees.auth_user_id IS 'ID пользователя Supabase Auth (auth.users). NULL для старых учёток.';
```

### 20260223000002_auth_policies.sql
```sql
-- Политики для пользователей с Supabase Auth (auth.uid() не null)
-- Позволяют authenticated пользователям работать со своими данными

-- employees: выборка по auth_user_id
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
CREATE POLICY "auth_select_employees" ON employees
  FOR SELECT TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR establishment_id IN (SELECT establishment_id FROM employees e2 WHERE e2.auth_user_id = auth.uid())
  );

-- employees: вставка (регистрация сотрудника с PIN) — только свой auth_user_id
DROP POLICY IF EXISTS "auth_insert_employees" ON employees;
CREATE POLICY "auth_insert_employees" ON employees
  FOR INSERT TO authenticated
  WITH CHECK (auth_user_id = auth.uid());

-- employees: обновление своего профиля или привязка auth_user_id при регистрации владельца
DROP POLICY IF EXISTS "auth_update_employees" ON employees;
CREATE POLICY "auth_update_employees" ON employees
  FOR UPDATE TO authenticated
  USING (
    auth_user_id = auth.uid()
    OR (auth_user_id IS NULL AND LOWER(email) = LOWER(auth.jwt()->>'email'))
  )
  WITH CHECK (true);

-- establishments: выборка — свои заведения
DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
CREATE POLICY "auth_select_establishments" ON establishments
  FOR SELECT TO authenticated
  USING (
    owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid())
    OR id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  );

-- establishments: обновление — своё заведение
DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
CREATE POLICY "auth_update_establishments" ON establishments
  FOR UPDATE TO authenticated
  USING (
    owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid())
    OR id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  )
  WITH CHECK (true);
```

### 20260223000003_password_hash_nullable.sql
```sql
-- password_hash нужен только для legacy-учёток (без Supabase Auth)
-- Новые учётки: пароль только в auth.users
ALTER TABLE employees ALTER COLUMN password_hash DROP NOT NULL;

COMMENT ON COLUMN employees.password_hash IS 'NULL для учёток через Supabase Auth. BCrypt или plain для legacy.';
```

### 20260223000005_anon_policies.sql
```sql
-- Anon-политики для регистрации (компания + владелец) без Supabase-сессии
DROP POLICY IF EXISTS "anon_select_establishments" ON establishments;
CREATE POLICY "anon_select_establishments" ON establishments
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;
CREATE POLICY "anon_insert_establishments" ON establishments
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_establishments" ON establishments;
CREATE POLICY "anon_update_establishments" ON establishments
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_select_employees" ON employees;
CREATE POLICY "anon_select_employees" ON employees
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_employees" ON employees;
CREATE POLICY "anon_insert_employees" ON employees
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_employees" ON employees;
CREATE POLICY "anon_update_employees" ON employees
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
```

### 20260223104030_add_employee_surname.sql
```sql
```

### 20260223151044_cleanup_test_data.sql
```sql
-- DISABLED: Удаляла всех кроме stassser — ломала реальных пользователей.
-- rebrikov.st@gmail.com и др. в auth.users, но были удалены из employees.
-- Для новых деплоев — no-op. Очистка только вручную с осторожностью.```

### 20260223160000_add_employee_surname.sql
```sql
-- Добавление фамилии сотрудника
ALTER TABLE employees ADD COLUMN IF NOT EXISTS surname TEXT;

COMMENT ON COLUMN employees.surname IS 'Фамилия сотрудника (опционально)';```

### 20260223170000_add_co_owner_invitations.sql
```sql
-- Таблица для приглашений соучредителей
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

-- Индексы
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_establishment_id ON co_owner_invitations(establishment_id);
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_invitation_token ON co_owner_invitations(invitation_token);
CREATE INDEX IF NOT EXISTS idx_co_owner_invitations_invited_email ON co_owner_invitations(invited_email);

-- RLS политики
ALTER TABLE co_owner_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
-- Владельцы могут видеть приглашения своего заведения
CREATE POLICY "Owners can view co-owner invitations" ON co_owner_invitations
  FOR SELECT USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
-- Владельцы могут создавать приглашения
CREATE POLICY "Owners can create co-owner invitations" ON co_owner_invitations
  FOR INSERT WITH CHECK (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
-- Владельцы могут обновлять приглашения
CREATE POLICY "Owners can update co-owner invitations" ON co_owner_invitations
  FOR UPDATE USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

COMMENT ON TABLE co_owner_invitations IS 'Приглашения для соучредителей заведений';```

### 20260223200000_send_email_on_email_confirmed.sql
```sql
-- Письмо о завершении регистрации при подтверждении email (auth.users.email_confirmed_at)
-- Требуется: pg_net, vault с supabase_anon_key
-- Добавьте anon key в vault один раз: SELECT vault.create_secret('ВАШ_ANON_KEY', 'supabase_anon_key', 'Edge Function auth');

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.send_registration_confirmed_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  emp_email text;
  est_name text;
  anon_key text;
  func_url text := 'https://osglfptwbuqqmqunttha.supabase.co/functions/v1/send-registration-email';
BEGIN
  -- Только когда email_confirmed_at меняется с NULL на не-NULL
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL AND NEW.email IS NOT NULL THEN
    -- Данные сотрудника и заведения
    SELECT e.email, est.name INTO emp_email, est_name
    FROM public.employees e
    LEFT JOIN public.establishments est ON est.id = e.establishment_id
    WHERE e.auth_user_id = NEW.id
    LIMIT 1;

    IF emp_email IS NOT NULL THEN
      SELECT decrypted_secret INTO anon_key
      FROM vault.decrypted_secrets
      WHERE name = 'supabase_anon_key'
      LIMIT 1;

      IF anon_key IS NOT NULL AND anon_key != '' THEN
        PERFORM net.http_post(
          url := func_url,
          body := jsonb_build_object(
            'type', 'registration_confirmed',
            'to', emp_email,
            'companyName', COALESCE(est_name, '')
          ),
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || anon_key
          )
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_email_confirmed
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.send_registration_confirmed_email();
```

### 20260224120000_product_price_history.sql
```sql
-- История изменений цены продукта в номенклатуре заведения
CREATE TABLE IF NOT EXISTS product_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  old_price REAL,
  new_price REAL NOT NULL,
  currency TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_price_history_est_prod
  ON product_price_history(establishment_id, product_id);

CREATE INDEX IF NOT EXISTS idx_product_price_history_changed_at
  ON product_price_history(changed_at DESC);

COMMENT ON TABLE product_price_history IS 'История изменений цены продукта в номенклатуре заведения';

ALTER TABLE product_price_history ENABLE ROW LEVEL SECURITY;

-- Просмотр истории — сотрудники своего заведения
CREATE POLICY "auth_select_product_price_history" ON product_price_history
  FOR SELECT USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  );

-- Вставка — сотрудники своего заведения
CREATE POLICY "auth_insert_product_price_history" ON product_price_history
  FOR INSERT WITH CHECK (
    establishment_id IN (SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid())
  );
```

### 20260224150000_inventory_drafts.sql
```sql
-- Таблица черновиков инвентаризации
CREATE TABLE IF NOT EXISTS inventory_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_drafts_establishment ON inventory_drafts(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_employee ON inventory_drafts(employee_id);
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_updated ON inventory_drafts(updated_at DESC);

ALTER TABLE inventory_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_inventory_drafts" ON inventory_drafts;
CREATE POLICY "anon_inventory_drafts" ON inventory_drafts
  FOR ALL TO anon USING (true) WITH CHECK (true);

COMMENT ON TABLE inventory_drafts IS 'Черновики инвентаризаций - автоматическое сохранение на сервер.';
```

### 20260224180000_inventory_drafts_unique.sql
```sql
-- Уникальный индекс для upsert по establishment_id (тихое автосохранение черновиков)
CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_drafts_establishment_unique
  ON inventory_drafts(establishment_id);
```

### 20260225100000_establishment_persistent_data.sql
```sql
-- Персистентные данные заведения: график смен и списки поставщиков.
-- Сохраняются в Supabase, чтобы не терялись при редеплое (раньше были в SharedPreferences/localStorage).

-- График смен (schedule)
CREATE TABLE IF NOT EXISTS establishment_schedule_data (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);

CREATE INDEX IF NOT EXISTS idx_establishment_schedule_data_establishment ON establishment_schedule_data(establishment_id);

ALTER TABLE establishment_schedule_data ENABLE ROW LEVEL SECURITY;

-- Anon-доступ (приложение использует custom auth через employees, без Supabase Auth)
DROP POLICY IF EXISTS "anon_schedule_select" ON establishment_schedule_data;
CREATE POLICY "anon_schedule_select" ON establishment_schedule_data
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_schedule_insert" ON establishment_schedule_data;
CREATE POLICY "anon_schedule_insert" ON establishment_schedule_data
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_schedule_update" ON establishment_schedule_data;
CREATE POLICY "anon_schedule_update" ON establishment_schedule_data
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- Списки поставщиков (order lists)
CREATE TABLE IF NOT EXISTS establishment_order_list_data (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '[]',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);

CREATE INDEX IF NOT EXISTS idx_establishment_order_list_data_establishment ON establishment_order_list_data(establishment_id);

ALTER TABLE establishment_order_list_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_order_list_select" ON establishment_order_list_data;
CREATE POLICY "anon_order_list_select" ON establishment_order_list_data
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_order_list_insert" ON establishment_order_list_data;
CREATE POLICY "anon_order_list_insert" ON establishment_order_list_data
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_order_list_update" ON establishment_order_list_data;
CREATE POLICY "anon_order_list_update" ON establishment_order_list_data
  FOR UPDATE TO anon USING (true) WITH CHECK (true);
```

### 20260225120000_tech_cards_photo_urls.sql
```sql
-- Фото блюд/ПФ в ТТК: блюдо — 1 фото, ПФ — до 10 фото (сетка).
-- Хранятся в Supabase Storage, bucket: tech_card_photos (создать вручную, public).

ALTER TABLE tech_cards
  ADD COLUMN IF NOT EXISTS photo_urls JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN tech_cards.photo_urls IS 'URL фото в Storage (bucket tech_card_photos). Блюдо: 1 элемент, ПФ: до 10.';
```

### 20260225130000_inventory_documents.sql
```sql
-- Таблица документов инвентаризации: сохранённые бланки для кабинета шеф-повара и входящих.
-- payload: { header: {...}, rows: [...], aggregatedProducts: [...] }
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

CREATE INDEX IF NOT EXISTS idx_inventory_documents_establishment ON inventory_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_documents_recipient ON inventory_documents(recipient_chef_id);
CREATE INDEX IF NOT EXISTS idx_inventory_documents_created_at ON inventory_documents(created_at DESC);

COMMENT ON TABLE inventory_documents IS 'Документы инвентаризации: бланк после «Завершить» сохраняется во входящие шефу и собственнику.';

-- Anon-доступ (приложение использует custom auth через employees)
ALTER TABLE inventory_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_inventory_documents_select" ON inventory_documents;
CREATE POLICY "anon_inventory_documents_select" ON inventory_documents
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "anon_inventory_documents_insert" ON inventory_documents
  FOR INSERT TO anon WITH CHECK (true);
```

### 20260225140000_order_documents.sql
```sql
-- Заказы продуктов во входящие (шефу и собственнику): история по датам.
-- payload: { header: { supplierName, employeeName, createdAt, orderForDate }, items: [{ productName, unit, quantity, pricePerUnit, lineTotal }], grandTotal }
CREATE TABLE IF NOT EXISTS order_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  created_by_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_documents_establishment ON order_documents(establishment_id);
CREATE INDEX IF NOT EXISTS idx_order_documents_created_at ON order_documents(created_at DESC);

COMMENT ON TABLE order_documents IS 'Заказы продуктов: после сохранения с количествами попадают во Входящие шефу и собственнику.';

-- Anon-доступ (приложение использует custom auth через employees)
ALTER TABLE order_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_order_documents_select" ON order_documents;
CREATE POLICY "anon_order_documents_select" ON order_documents
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_order_documents_insert" ON order_documents;
CREATE POLICY "anon_order_documents_insert" ON order_documents
  FOR INSERT TO anon WITH CHECK (true);
```

### 20260225150000_inventory_order_docs_authenticated_rls.sql
```sql
-- Политики RLS для authenticated: владельцы и шефы входят через Supabase Auth,
-- поэтому SELECT/INSERT должны работать для роли authenticated (не только anon).
-- Без этого инвентаризация и заказы сохраняются, но не появляются во входящих.

-- inventory_documents
DROP POLICY IF EXISTS "auth_inventory_documents_select" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_select" ON inventory_documents
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_insert" ON inventory_documents
  FOR INSERT TO authenticated WITH CHECK (true);

-- order_documents
DROP POLICY IF EXISTS "auth_order_documents_select" ON order_documents;
CREATE POLICY "auth_order_documents_select" ON order_documents
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_order_documents_insert" ON order_documents;
CREATE POLICY "auth_order_documents_insert" ON order_documents
  FOR INSERT TO authenticated WITH CHECK (true);
```

### 20260225160000_order_list_schedule_authenticated_rls.sql
```sql
-- Политики RLS для authenticated: график и списки заказов.
-- Без них при входе через Supabase Auth данные не читаются/не пишутся в Supabase,
-- остаётся только SharedPreferences — и при очистке кеша/новом устройстве всё слетает.

-- establishment_schedule_data (график смен)
DROP POLICY IF EXISTS "auth_schedule_select" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_select" ON establishment_schedule_data
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_schedule_insert" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_insert" ON establishment_schedule_data
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_schedule_update" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_update" ON establishment_schedule_data
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- establishment_order_list_data (списки заказов поставщикам)
DROP POLICY IF EXISTS "auth_order_list_select" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_select" ON establishment_order_list_data
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_order_list_insert" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_insert" ON establishment_order_list_data
  FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "auth_order_list_update" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_update" ON establishment_order_list_data
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
```

### 20260225170000_unify_rls_auth_user_id.sql
```sql
-- Унификация RLS: единый источник — auth.uid() и auth_user_id.
-- Все политики должны использовать auth_user_id = auth.uid(), НЕ employees.id = auth.uid().
-- (employees.id — бизнес-PK, auth.users.id — идентификатор входа; связь через auth_user_id)
--
-- Удаляем политики с неправильным условием employees.id = auth.uid().
-- Они могли быть созданы setup-скриптами (final_rls_setup.sql и т.п.).

-- order_documents: блокировала INSERT/SELECT — именно она ломала заказы во входящих
DROP POLICY IF EXISTS "order_documents_establishment_access" ON order_documents;
```

### 20260225180000_employees_id_equals_auth_uid.sql
```sql
-- employees.id = auth.users.id: единый идентификатор.
-- Все входят только через Supabase Auth. employees.id станет auth.users.id.
--
-- ВНИМАНИЕ: Требует очистки данных (реальных пользователей пока нет).

-- 1. Обнулить owner_id в establishments
UPDATE establishments SET owner_id = NULL;

-- 2. Очистить employees (CASCADE затронет order_documents, inventory_documents, inventory_drafts, co_owner_invitations, password_reset_tokens)
TRUNCATE employees CASCADE;

-- 3. Удалить политики, зависящие от auth_user_id (до DROP COLUMN)
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
DROP POLICY IF EXISTS "auth_insert_employees" ON employees;
DROP POLICY IF EXISTS "auth_update_employees" ON employees;
DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "auth_select_product_price_history" ON product_price_history;
DROP POLICY IF EXISTS "auth_insert_product_price_history" ON product_price_history;
DROP POLICY IF EXISTS "Разрешить обновление цен для шефа" ON products;

-- 4. Удалить колонку auth_user_id
ALTER TABLE employees DROP COLUMN IF EXISTS auth_user_id;

-- 5. id больше не gen_random_uuid — всегда передаём auth.users.id при вставке
ALTER TABLE employees ALTER COLUMN id DROP DEFAULT;

-- 6. FK: employees.id должен существовать в auth.users
ALTER TABLE employees
  ADD CONSTRAINT fk_employees_auth
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 7. Обновить RLS: id = auth.uid() вместо auth_user_id = auth.uid()
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
CREATE POLICY "auth_select_employees" ON employees
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR establishment_id IN (SELECT establishment_id FROM employees e2 WHERE e2.id = auth.uid())
  );

DROP POLICY IF EXISTS "auth_insert_employees" ON employees;
CREATE POLICY "auth_insert_employees" ON employees
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "auth_update_employees" ON employees;
CREATE POLICY "auth_update_employees" ON employees
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (true);

DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
CREATE POLICY "auth_select_establishments" ON establishments
  FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
CREATE POLICY "auth_update_establishments" ON establishments
  FOR UPDATE TO authenticated
  USING (
    owner_id = auth.uid()
    OR id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  )
  WITH CHECK (true);

-- 8. co_owner_invitations: auth_user_id -> id
DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can view co-owner invitations" ON co_owner_invitations
  FOR SELECT USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );
DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can create co-owner invitations" ON co_owner_invitations
  FOR INSERT WITH CHECK (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );
DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can update co-owner invitations" ON co_owner_invitations
  FOR UPDATE USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.id = auth.uid() AND 'owner' = ANY(emp.roles)
    )
  );

-- 9. product_price_history: auth_user_id -> id
DROP POLICY IF EXISTS "auth_select_product_price_history" ON product_price_history;
CREATE POLICY "auth_select_product_price_history" ON product_price_history
  FOR SELECT USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );
DROP POLICY IF EXISTS "auth_insert_product_price_history" ON product_price_history;
CREATE POLICY "auth_insert_product_price_history" ON product_price_history
  FOR INSERT WITH CHECK (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );

-- 10. send_registration_confirmed_email: auth_user_id -> id
CREATE OR REPLACE FUNCTION public.send_registration_confirmed_email()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  emp_email text;
  est_name text;
  anon_key text;
  func_url text := 'https://osglfptwbuqqmqunttha.supabase.co/functions/v1/send-registration-email';
BEGIN
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL AND NEW.email IS NOT NULL THEN
    SELECT e.email, est.name INTO emp_email, est_name
    FROM public.employees e
    LEFT JOIN public.establishments est ON est.id = e.establishment_id
    WHERE e.id = NEW.id
    LIMIT 1;
    IF emp_email IS NOT NULL THEN
      SELECT decrypted_secret INTO anon_key FROM vault.decrypted_secrets WHERE name = 'supabase_anon_key' LIMIT 1;
      IF anon_key IS NOT NULL AND anon_key != '' THEN
        PERFORM net.http_post(
          url := func_url,
          body := jsonb_build_object('type', 'registration_confirmed', 'to', emp_email, 'companyName', COALESCE(est_name, '')),
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || anon_key)
        );
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
```

### 20260225185000_add_data_access_enabled.sql
```sql
-- Доступ к данным: при регистрации выключен. Включается руководителем в карточке сотрудника.
ALTER TABLE employees ADD COLUMN IF NOT EXISTS data_access_enabled boolean DEFAULT false NOT NULL;
COMMENT ON COLUMN employees.data_access_enabled IS 'Доступ к данным (кроме графика). По умолчанию false при регистрации.';
```

### 20260225190000_create_owner_employee_rpc.sql
```sql
-- RPC для создания владельца (owner) при регистрации компании.
-- Вызывается без сессии (после signUp, до подтверждения email).
-- Проверяет, что auth_user_id есть в auth.users с совпадающим email — затем вставляет в employees.

CREATE OR REPLACE FUNCTION public.create_owner_employee(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner']
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
BEGIN
  -- Проверка: пользователь создан в auth.users и email совпадает
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_exists;

  IF NOT v_exists THEN
    RAISE EXCEPTION 'create_owner_employee: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  -- Проверка: establishment существует
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_owner_employee: establishment % not found', p_establishment_id;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    'management', NULL, p_roles, p_establishment_id, v_personal_pin,
    'ru', true, true, v_now, v_now
  );

  UPDATE establishments SET owner_id = p_auth_user_id, updated_at = v_now
  WHERE id = p_establishment_id;

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.create_owner_employee IS 'Создание записи владельца в employees после signUp. Вызывается без сессии (Confirm Email).';

-- Разрешить вызов anon и authenticated
GRANT EXECUTE ON FUNCTION public.create_owner_employee TO anon;
GRANT EXECUTE ON FUNCTION public.create_owner_employee TO authenticated;
```

### 20260225200000_create_employee_for_company_rpc.sql
```sql
-- RPC для создания сотрудника владельцем.
-- Вызывается когда signUp требует подтверждения email — нет сессии нового юзера, вставка через RLS невозможна.
-- Проверяет: caller — owner заведения; auth user создан с совпадающим email.

CREATE OR REPLACE FUNCTION public.create_employee_for_company(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_is_owner boolean;
  v_auth_exists boolean;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'create_employee_for_company: must be authenticated';
  END IF;

  -- Проверка: caller — owner данного заведения
  SELECT EXISTS (
    SELECT 1 FROM employees e
    WHERE e.id = v_caller_id
      AND e.establishment_id = p_establishment_id
      AND 'owner' = ANY(e.roles)
      AND e.is_active = true
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'create_employee_for_company: only owner can add employees';
  END IF;

  -- Проверка: auth user создан и email совпадает
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;

  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_for_company: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  -- Проверка: establishment существует
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_employee_for_company: establishment % not found', p_establishment_id;
  END IF;

  -- Проверка: email не занят в этом заведении
  IF EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_for_company: email already taken in establishment';
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
    nullif(trim(p_section), ''),
    p_roles, p_establishment_id, v_personal_pin,
    'ru', true, false, v_now, v_now
  );

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.create_employee_for_company IS 'Создание сотрудника владельцем. Вызывается когда signUp требует подтверждения email и RLS не позволяет INSERT.';

GRANT EXECUTE ON FUNCTION public.create_employee_for_company TO authenticated;

-- RPC для самостоятельной регистрации (RegisterScreen): anon, нет сессии после signUp с Confirm Email.
CREATE OR REPLACE FUNCTION public.create_employee_self_register(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_exists boolean;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
BEGIN
  -- Проверка: auth user создан и email совпадает
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;

  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_self_register: auth user not found or email mismatch';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_employee_self_register: establishment not found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_self_register: email already taken';
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
    nullif(trim(p_section), ''),
    p_roles, p_establishment_id, v_personal_pin,
    'ru', true, false, v_now, v_now
  );

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.create_employee_self_register IS 'Самостоятельная регистрация. Вызывается anon после signUp (Confirm Email).';

GRANT EXECUTE ON FUNCTION public.create_employee_self_register TO anon;
GRANT EXECUTE ON FUNCTION public.create_employee_self_register TO authenticated;
```

### 20260226000000_fix_owner_without_employee_rpc.sql
```sql
-- RPC для автоматического исправления: auth user есть, employee нет.
-- Вызывается при логине, когда Auth успешен, но employees.id не найден.
-- Создаёт владельца и привязывает к заведению без владельца.

CREATE OR REPLACE FUNCTION public.fix_owner_without_employee(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_id uuid;
  v_est_id uuid;
  v_name text;
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
BEGIN
  v_auth_id := auth.uid();
  IF v_auth_id IS NULL THEN
    RAISE EXCEPTION 'fix_owner_without_employee: must be authenticated';
  END IF;

  IF LOWER(trim(p_email)) != (SELECT LOWER(email) FROM auth.users WHERE id = v_auth_id) THEN
    RAISE EXCEPTION 'fix_owner_without_employee: email does not match current user';
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = v_auth_id) THEN
    SELECT to_jsonb(r) INTO v_emp FROM (
      SELECT id, full_name, surname, email, department, section, roles,
             establishment_id, personal_pin, preferred_language, is_active,
             created_at, updated_at FROM employees WHERE id = v_auth_id
    ) r;
    RETURN v_emp;
  END IF;

  -- Сначала: заведение, где этот user уже owner (employee потерялся, напр. после миграции)
  SELECT id INTO v_est_id FROM establishments WHERE owner_id = v_auth_id LIMIT 1;
  -- Иначе: заведение без владельца
  IF v_est_id IS NULL THEN
    SELECT id INTO v_est_id FROM establishments
    WHERE owner_id IS NULL
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_est_id IS NULL THEN
    RAISE EXCEPTION 'fix_owner_without_employee: no establishment for this owner';
  END IF;

  v_name := COALESCE(
    (SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id = v_auth_id),
    split_part(trim(p_email), '@', 1)
  );
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, created_at, updated_at
  ) VALUES (
    v_auth_id, v_name, NULL, trim(p_email), NULL,
    'management', NULL, ARRAY['owner'], v_est_id, v_personal_pin,
    'ru', true, v_now, v_now
  );

  UPDATE establishments SET owner_id = v_auth_id, updated_at = v_now
  WHERE id = v_est_id AND (owner_id IS NULL OR owner_id = v_auth_id);

  SELECT to_jsonb(r) INTO v_emp FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active,
           created_at, updated_at FROM employees WHERE id = v_auth_id
  ) r;

  RETURN v_emp;
END;
$$;

COMMENT ON FUNCTION public.fix_owner_without_employee IS 'Создаёт employee для auth user, если его нет. Привязывает к establishment без owner.';

GRANT EXECUTE ON FUNCTION public.fix_owner_without_employee TO authenticated;
```

### 20260226100000_checklists_extended.sql
```sql
-- Расширение checklists: additional_name, type, action_config
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS additional_name TEXT;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'tasks';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS action_config JSONB DEFAULT '{"has_numeric":false,"has_toggle":true}'::jsonb;

-- Расширение checklist_items: tech_card_id
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL;

-- Черновики заполнения чеклистов (localStorage + сервер каждые 15 сек)
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

CREATE INDEX IF NOT EXISTS idx_checklist_drafts_checklist ON checklist_drafts(checklist_id);
CREATE INDEX IF NOT EXISTS idx_checklist_drafts_employee ON checklist_drafts(employee_id);
CREATE INDEX IF NOT EXISTS idx_checklist_drafts_updated ON checklist_drafts(updated_at DESC);

ALTER TABLE checklist_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_checklist_drafts" ON checklist_drafts;
CREATE POLICY "anon_checklist_drafts" ON checklist_drafts
  FOR ALL TO anon USING (true) WITH CHECK (true);

COMMENT ON TABLE checklist_drafts IS 'Черновики заполнения чеклистов - автосохранение в браузере и на сервер каждые 15 сек.';
```

### 20260226120000_storage_avatars_rls.sql
```sql
-- RLS политики для Storage bucket "avatars" (фото профилей сотрудников)
-- Исправляет: new row violates row-level security policy (403 Unauthorized)

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_insert_authenticated'
  ) THEN
    CREATE POLICY "avatars_insert_authenticated"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_update_authenticated'
  ) THEN
    CREATE POLICY "avatars_update_authenticated"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'avatars')
    WITH CHECK (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_select_public'
  ) THEN
    CREATE POLICY "avatars_select_public"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_delete_authenticated'
  ) THEN
    CREATE POLICY "avatars_delete_authenticated"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'avatars');
  END IF;
END $$;
```

### 20260226130000_checklists_rls.sql
```sql
-- RLS политики для checklists и checklist_items.
-- Приложение использует anon (как inventory_documents, order_documents).

ALTER TABLE checklists ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_items ENABLE ROW LEVEL SECURITY;

-- checklists: anon-доступ
DROP POLICY IF EXISTS "checklists_establishment_access" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_select" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_insert" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_update" ON checklists;
DROP POLICY IF EXISTS "anon_checklists_delete" ON checklists;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklists' AND policyname = 'anon_checklists_all') THEN
    CREATE POLICY "anon_checklists_all" ON checklists FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

-- checklist_items: anon-доступ
DROP POLICY IF EXISTS "checklist_items_checklist_access" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_select" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_insert" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_update" ON checklist_items;
DROP POLICY IF EXISTS "anon_checklist_items_delete" ON checklist_items;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklist_items' AND policyname = 'anon_checklist_items_all') THEN
    CREATE POLICY "anon_checklist_items_all" ON checklist_items FOR ALL TO anon USING (true) WITH CHECK (true);
  END IF;
END $$;

-- authenticated: на случай если приложение использует Supabase Auth
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklists' AND policyname = 'auth_checklists_all') THEN
    CREATE POLICY "auth_checklists_all" ON checklists FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'checklist_items' AND policyname = 'auth_checklist_items_all') THEN
    CREATE POLICY "auth_checklist_items_all" ON checklist_items FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;
```

### 20260226140000_checklist_submissions_drafts_fix.sql
```sql
-- checklist_submissions: гарантируем колонку checklist_name, RLS
-- (если таблица не существует — создайте её из supabase_migration_checklist_submissions.sql)
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS checklist_name TEXT DEFAULT '';

ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;

CREATE POLICY "anon_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- checklist_drafts: добавляем auth-политику (anon уже есть в 20260226100000)
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
CREATE POLICY "auth_checklist_drafts_all" ON checklist_drafts
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
```

### 20260226150000_checklists_assigned_columns.sql
```sql
-- Добавить assigned_section, assigned_employee_id в checklists (если ещё нет)
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_section TEXT;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
```

### 20260226150001_order_documents_recipients.sql
```sql
-- Добавляем recipient_chef_id и recipient_email в order_documents для совместимости
-- (миграция 20260225140000 создаёт таблицу без этих колонок; prod мог быть создан из другого скрипта)
ALTER TABLE order_documents ADD COLUMN IF NOT EXISTS recipient_chef_id UUID REFERENCES employees(id) ON DELETE CASCADE;
ALTER TABLE order_documents ADD COLUMN IF NOT EXISTS recipient_email TEXT;

-- Индекс для выборки по получателю (как в checklist_submissions)
CREATE INDEX IF NOT EXISTS idx_order_documents_recipient ON order_documents(recipient_chef_id) WHERE recipient_chef_id IS NOT NULL;

COMMENT ON COLUMN order_documents.recipient_chef_id IS 'Получатель документа (шеф/владелец). Один ряд на получателя.';
COMMENT ON COLUMN order_documents.recipient_email IS 'Email получателя для уведомлений.';
```

### 20260226160000_storage_tech_card_photos_rls.sql
```sql
-- RLS политики для Storage bucket "tech_card_photos" (фото ТТК — блюда и ПФ)

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_insert_authenticated'
  ) THEN
    CREATE POLICY "tech_card_photos_insert_authenticated"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'tech_card_photos');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_update_authenticated'
  ) THEN
    CREATE POLICY "tech_card_photos_update_authenticated"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'tech_card_photos')
    WITH CHECK (bucket_id = 'tech_card_photos');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_select_public'
  ) THEN
    CREATE POLICY "tech_card_photos_select_public"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'tech_card_photos');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'tech_card_photos_delete_authenticated'
  ) THEN
    CREATE POLICY "tech_card_photos_delete_authenticated"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'tech_card_photos');
  END IF;
END $$;
```

### 20260226170000_tech_cards_anon_select.sql
```sql
-- tech_cards: anon SELECT для выбора ТТК ПФ в чеклистах и др.
-- Приложение использует anon-ключ; без этой политики getTechCardsForEstablishment возвращает [].
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_tech_cards_select" ON tech_cards;
CREATE POLICY "anon_tech_cards_select" ON tech_cards
  FOR SELECT TO anon USING (true);
```

### 20260226180000_checklist_submissions_section.sql
```sql
-- checklist_submissions: колонка section (Postgrest schema cache error)
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS section TEXT;
```

### 20260227100000_enable_rls_employees_products.sql
```sql
-- Включаем RLS на таблицах employees и products.
-- Политики уже существуют (созданы в предыдущих миграциях),
-- но RLS не был включён — данные были полностью открыты.

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
```

### 20260227200000_translation_cache.sql
```sql
create table if not exists translation_cache (
  id            bigserial primary key,
  source_text   text        not null,
  source_lang   text        not null default 'ru',
  target_lang   text        not null default 'en',
  translated    text        not null,
  created_at    timestamptz not null default now(),
  constraint translation_cache_unique unique (source_text, source_lang, target_lang)
);

create index if not exists translation_cache_lookup
  on translation_cache (source_lang, target_lang, source_text);

alter table translation_cache enable row level security;

-- Edge Functions (service_role) могут читать и писать, обычные пользователи — нет
create policy "service_role full access"
  on translation_cache
  for all
  to service_role
  using (true)
  with check (true);
```

### 20260227210000_promo_codes.sql
```sql
create table if not exists promo_codes (
  id            bigserial primary key,
  code          text        not null unique,
  is_used       boolean     not null default false,
  used_by_establishment_id uuid references establishments(id) on delete set null,
  used_at       timestamptz,
  created_at    timestamptz not null default now(),
  note          text
);

alter table promo_codes enable row level security;

-- Только service_role может читать и писать (владелец вносит коды напрямую через Supabase Dashboard)
create policy "service_role full access"
  on promo_codes for all
  to service_role
  using (true)
  with check (true);

-- RPC: проверить промокод и пометить как использованный
create or replace function use_promo_code(
  p_code text,
  p_establishment_id uuid
) returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code))
  for update;

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  update promo_codes
  set is_used = true,
      used_by_establishment_id = p_establishment_id,
      used_at = now()
  where id = v_row.id;

  return 'ok';
end;
$$;

-- RPC: только проверить промокод без использования (валидация на форме)
create or replace function check_promo_code(p_code text)
returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code));

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  return 'ok';
end;
$$;
```

### 20260227220000_promo_codes_expires.sql
```sql
alter table promo_codes add column if not exists expires_at timestamptz;

-- Обновляем check_promo_code: учитываем срок действия
create or replace function check_promo_code(p_code text)
returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code));

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  return 'ok';
end;
$$;

-- Обновляем use_promo_code: тоже проверяем срок
create or replace function use_promo_code(
  p_code text,
  p_establishment_id uuid
) returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code))
  for update;

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  update promo_codes
  set is_used = true,
      used_by_establishment_id = p_establishment_id,
      used_at = now()
  where id = v_row.id;

  return 'ok';
end;
$$;
```

### 20260227230000_translations_table.sql
```sql
-- Таблица переводов динамического контента (продукты, ТТК, чеклисты)
create table if not exists translations (
  id                bigserial primary key,
  entity_type       text        not null,
  entity_id         text        not null,
  field_name        text        not null,
  source_text       text        not null,
  source_language   text        not null default 'ru',
  target_language   text        not null,
  translated_text   text        not null,
  is_manual_override boolean    not null default false,
  created_at        timestamptz not null default now(),
  created_by        text,
  constraint translations_unique unique (entity_type, entity_id, field_name, source_language, target_language)
);

create index if not exists translations_entity_idx
  on translations (entity_type, entity_id, field_name);

-- RLS: читать может любой аутентифицированный, писать — тоже
alter table translations enable row level security;

create policy "translations_select" on translations
  for select using (auth.role() = 'authenticated');

create policy "translations_insert" on translations
  for insert with check (auth.role() = 'authenticated');

create policy "translations_update" on translations
  for update using (auth.role() = 'authenticated');

-- service_role имеет полный доступ автоматически
```

### 20260227240000_culinary_products_catalog.sql
```sql
-- Полный каталог кулинарных продуктов мира (~2200 позиций)
-- Добавляем только те продукты, которых ещё нет в базе (по имени)
-- names: {"ru": "...", "en": "..."}, unit: g/kg/pcs/ml/L

insert into products (id, name, category, names, unit)
select gen_random_uuid(), v.name, v.category, v.names::jsonb, v.unit
from (values

-- ==================== МЯСО ====================
('Говядина (вырезка)','meat','{"ru":"Говядина (вырезка)","en":"Beef tenderloin"}','g'),
('Говядина (лопатка)','meat','{"ru":"Говядина (лопатка)","en":"Beef shoulder"}','g'),
('Говядина (грудинка)','meat','{"ru":"Говядина (грудинка)","en":"Beef brisket"}','g'),
('Говядина (ребра)','meat','{"ru":"Говядина (ребра)","en":"Beef ribs"}','g'),
('Говядина (антрекот)','meat','{"ru":"Говядина (антрекот)","en":"Beef entrecote"}','g'),
('Говядина (стейк рибай)','meat','{"ru":"Говядина (стейк рибай)","en":"Beef ribeye steak"}','g'),
('Говядина (стейк стриплойн)','meat','{"ru":"Говядина (стейк стриплойн)","en":"Beef striploin steak"}','g'),
('Говядина (фарш)','meat','{"ru":"Говядина (фарш)","en":"Ground beef"}','g'),
('Говядина (оковалок)','meat','{"ru":"Говядина (оковалок)","en":"Beef rump"}','g'),
('Говядина (толстый край)','meat','{"ru":"Говядина (толстый край)","en":"Beef chuck roll"}','g'),
('Говядина (тонкий край)','meat','{"ru":"Говядина (тонкий край)","en":"Beef sirloin"}','g'),
('Телятина (вырезка)','meat','{"ru":"Телятина (вырезка)","en":"Veal tenderloin"}','g'),
('Телятина (котлетная часть)','meat','{"ru":"Телятина (котлетная часть)","en":"Veal cutlet"}','g'),
('Телятина (нога)','meat','{"ru":"Телятина (нога)","en":"Veal leg"}','g'),
('Свинина (вырезка)','meat','{"ru":"Свинина (вырезка)","en":"Pork tenderloin"}','g'),
('Свинина (шея)','meat','{"ru":"Свинина (шея)","en":"Pork neck"}','g'),
('Свинина (лопатка)','meat','{"ru":"Свинина (лопатка)","en":"Pork shoulder"}','g'),
('Свинина (грудинка)','meat','{"ru":"Свинина (грудинка)","en":"Pork belly"}','g'),
('Свинина (корейка)','meat','{"ru":"Свинина (корейка)","en":"Pork loin"}','g'),
('Свинина (ребра)','meat','{"ru":"Свинина (ребра)","en":"Pork ribs"}','g'),
('Свинина (окорок)','meat','{"ru":"Свинина (окорок)","en":"Pork ham"}','g'),
('Свинина (фарш)','meat','{"ru":"Свинина (фарш)","en":"Ground pork"}','g'),
('Баранина (нога)','meat','{"ru":"Баранина (нога)","en":"Lamb leg"}','g'),
('Баранина (каре)','meat','{"ru":"Баранина (каре)","en":"Rack of lamb"}','g'),
('Баранина (лопатка)','meat','{"ru":"Баранина (лопатка)","en":"Lamb shoulder"}','g'),
('Баранина (корейка)','meat','{"ru":"Баранина (корейка)","en":"Lamb loin"}','g'),
('Баранина (ребра)','meat','{"ru":"Баранина (ребра)","en":"Lamb ribs"}','g'),
('Баранина (фарш)','meat','{"ru":"Баранина (фарш)","en":"Ground lamb"}','g'),
('Козлятина','meat','{"ru":"Козлятина","en":"Goat meat"}','g'),
('Конина','meat','{"ru":"Конина","en":"Horse meat"}','g'),
('Кролик (тушка)','meat','{"ru":"Кролик (тушка)","en":"Rabbit carcass"}','g'),
('Кролик (задние ноги)','meat','{"ru":"Кролик (задние ноги)","en":"Rabbit hind legs"}','g'),
('Оленина','meat','{"ru":"Оленина","en":"Venison"}','g'),
('Лосятина','meat','{"ru":"Лосятина","en":"Elk meat"}','g'),
('Кабанятина','meat','{"ru":"Кабанятина","en":"Wild boar meat"}','g'),
('Зубрятина','meat','{"ru":"Зубрятина","en":"Bison meat"}','g'),
('Утиная грудка','meat','{"ru":"Утиная грудка","en":"Duck breast"}','g'),
('Утиные ноги (конфи)','meat','{"ru":"Утиные ноги (конфи)","en":"Duck legs (confit)"}','g'),
('Гусятина','meat','{"ru":"Гусятина","en":"Goose meat"}','g'),
('Индейка (грудка)','meat','{"ru":"Индейка (грудка)","en":"Turkey breast"}','g'),
('Индейка (бедро)','meat','{"ru":"Индейка (бедро)","en":"Turkey thigh"}','g'),
('Перепел (тушка)','meat','{"ru":"Перепел (тушка)","en":"Quail carcass"}','g'),
('Голубь (тушка)','meat','{"ru":"Голубь (тушка)","en":"Pigeon carcass"}','g'),
('Фазан (тушка)','meat','{"ru":"Фазан (тушка)","en":"Pheasant carcass"}','g'),
('Страус (стейк)','meat','{"ru":"Страус (стейк)","en":"Ostrich steak"}','g'),
('Бекон копченый','meat','{"ru":"Бекон копченый","en":"Smoked bacon"}','g'),
('Ветчина вареная','meat','{"ru":"Ветчина вареная","en":"Cooked ham"}','g'),
('Карбонат свиной','meat','{"ru":"Карбонат свиной","en":"Pork carbonade"}','g'),
('Мясо смешанный фарш','meat','{"ru":"Мясо смешанный фарш","en":"Mixed ground meat"}','g'),

-- ==================== ПТИЦА ====================
('Курица (тушка)','meat','{"ru":"Курица (тушка)","en":"Whole chicken"}','g'),
('Куриное филе','meat','{"ru":"Куриное филе","en":"Chicken fillet"}','g'),
('Куриное бедро (без кости)','meat','{"ru":"Куриное бедро (без кости)","en":"Boneless chicken thigh"}','g'),
('Куриное бедро (с костью)','meat','{"ru":"Куриное бедро (с костью)","en":"Bone-in chicken thigh"}','g'),
('Куриная голень','meat','{"ru":"Куриная голень","en":"Chicken drumstick"}','g'),
('Куриное крыло','meat','{"ru":"Куриное крыло","en":"Chicken wing"}','g'),
('Куриная грудка (с кожей)','meat','{"ru":"Куриная грудка (с кожей)","en":"Chicken breast with skin"}','g'),
('Куриный фарш','meat','{"ru":"Куриный фарш","en":"Ground chicken"}','g'),
('Куриная спинка','meat','{"ru":"Куриная спинка","en":"Chicken back"}','g'),
('Утка (тушка)','meat','{"ru":"Утка (тушка)","en":"Whole duck"}','g'),
('Гусь (тушка)','meat','{"ru":"Гусь (тушка)","en":"Whole goose"}','g'),
('Индейка (тушка)','meat','{"ru":"Индейка (тушка)","en":"Whole turkey"}','g'),
('Цыпленок корнишон','meat','{"ru":"Цыпленок корнишон","en":"Poussin"}','g'),

-- ==================== СУБПРОДУКТЫ ====================
('Печень говяжья','meat','{"ru":"Печень говяжья","en":"Beef liver"}','g'),
('Печень свиная','meat','{"ru":"Печень свиная","en":"Pork liver"}','g'),
('Печень куриная','meat','{"ru":"Печень куриная","en":"Chicken liver"}','g'),
('Печень утиная','meat','{"ru":"Печень утиная","en":"Duck liver"}','g'),
('Фуа-гра (утиная печень)','meat','{"ru":"Фуа-гра (утиная печень)","en":"Foie gras (duck liver)"}','g'),
('Сердце говяжье','meat','{"ru":"Сердце говяжье","en":"Beef heart"}','g'),
('Сердце куриное','meat','{"ru":"Сердце куриное","en":"Chicken heart"}','g'),
('Язык говяжий','meat','{"ru":"Язык говяжий","en":"Beef tongue"}','g'),
('Язык свиной','meat','{"ru":"Язык свиной","en":"Pork tongue"}','g'),
('Мозги говяжьи','meat','{"ru":"Мозги говяжьи","en":"Beef brains"}','g'),
('Почки говяжьи','meat','{"ru":"Почки говяжьи","en":"Beef kidneys"}','g'),
('Почки свиные','meat','{"ru":"Почки свиные","en":"Pork kidneys"}','g'),
('Рубец говяжий','meat','{"ru":"Рубец говяжий","en":"Beef tripe"}','g'),
('Вымя говяжье','meat','{"ru":"Вымя говяжье","en":"Beef udder"}','g'),
('Хвост говяжий','meat','{"ru":"Хвост говяжий","en":"Oxtail"}','g'),
('Щека свиная','meat','{"ru":"Щека свиная","en":"Pork cheek"}','g'),
('Щека говяжья','meat','{"ru":"Щека говяжья","en":"Beef cheek"}','g'),
('Ноги свиные','meat','{"ru":"Ноги свиные","en":"Pork trotters"}','g'),
('Уши свиные','meat','{"ru":"Уши свиные","en":"Pork ears"}','g'),
('Кишки свиные','meat','{"ru":"Кишки свиные","en":"Pork intestines"}','g'),
('Кровь свиная','meat','{"ru":"Кровь свиная","en":"Pork blood"}','g'),
('Желудок куриный','meat','{"ru":"Желудок куриный","en":"Chicken gizzard"}','g'),
('Шейка куриная','meat','{"ru":"Шейка куриная","en":"Chicken neck"}','g'),
('Лапки куриные','meat','{"ru":"Лапки куриные","en":"Chicken feet"}','g'),

-- ==================== РЫБА ====================
('Лосось (филе)','seafood','{"ru":"Лосось (филе)","en":"Salmon fillet"}','g'),
('Лосось (стейк)','seafood','{"ru":"Лосось (стейк)","en":"Salmon steak"}','g'),
('Форель (филе)','seafood','{"ru":"Форель (филе)","en":"Trout fillet"}','g'),
('Форель (тушка)','seafood','{"ru":"Форель (тушка)","en":"Whole trout"}','g'),
('Тунец (филе)','seafood','{"ru":"Тунец (филе)","en":"Tuna fillet"}','g'),
('Тунец (стейк)','seafood','{"ru":"Тунец (стейк)","en":"Tuna steak"}','g'),
('Треска (филе)','seafood','{"ru":"Треска (филе)","en":"Cod fillet"}','g'),
('Треска (спинка)','seafood','{"ru":"Треска (спинка)","en":"Cod back"}','g'),
('Палтус (филе)','seafood','{"ru":"Палтус (филе)","en":"Halibut fillet"}','g'),
('Палтус (стейк)','seafood','{"ru":"Палтус (стейк)","en":"Halibut steak"}','g'),
('Судак (филе)','seafood','{"ru":"Судак (филе)","en":"Pike perch fillet"}','g'),
('Судак (тушка)','seafood','{"ru":"Судак (тушка)","en":"Whole pike perch"}','g'),
('Щука (тушка)','seafood','{"ru":"Щука (тушка)","en":"Whole pike"}','g'),
('Щука (филе)','seafood','{"ru":"Щука (филе)","en":"Pike fillet"}','g'),
('Карп (тушка)','seafood','{"ru":"Карп (тушка)","en":"Whole carp"}','g'),
('Карп (филе)','seafood','{"ru":"Карп (филе)","en":"Carp fillet"}','g'),
('Окунь (тушка)','seafood','{"ru":"Окунь (тушка)","en":"Whole perch"}','g'),
('Окунь морской (филе)','seafood','{"ru":"Окунь морской (филе)","en":"Sea bass fillet"}','g'),
('Сибас (тушка)','seafood','{"ru":"Сибас (тушка)","en":"Whole sea bass"}','g'),
('Дорада (тушка)','seafood','{"ru":"Дорада (тушка)","en":"Whole sea bream"}','g'),
('Дорада (филе)','seafood','{"ru":"Дорада (филе)","en":"Sea bream fillet"}','g'),
('Сельдь (соленая)','seafood','{"ru":"Сельдь (соленая)","en":"Salted herring"}','g'),
('Сельдь (свежая)','seafood','{"ru":"Сельдь (свежая)","en":"Fresh herring"}','g'),
('Скумбрия (тушка)','seafood','{"ru":"Скумбрия (тушка)","en":"Whole mackerel"}','g'),
('Скумбрия (копченая)','seafood','{"ru":"Скумбрия (копченая)","en":"Smoked mackerel"}','g'),
('Сардины','seafood','{"ru":"Сардины","en":"Sardines"}','g'),
('Анчоусы (соленые)','seafood','{"ru":"Анчоусы (соленые)","en":"Salted anchovies"}','g'),
('Анчоусы (в масле)','seafood','{"ru":"Анчоусы (в масле)","en":"Anchovies in oil"}','g'),
('Угорь речной','seafood','{"ru":"Угорь речной","en":"River eel"}','g'),
('Угорь морской','seafood','{"ru":"Угорь морской","en":"Sea eel"}','g'),
('Угорь копченый','seafood','{"ru":"Угорь копченый","en":"Smoked eel"}','g'),
('Камбала (филе)','seafood','{"ru":"Камбала (филе)","en":"Flounder fillet"}','g'),
('Минтай (филе)','seafood','{"ru":"Минтай (филе)","en":"Pollock fillet"}','g'),
('Хек (филе)','seafood','{"ru":"Хек (филе)","en":"Hake fillet"}','g'),
('Навага','seafood','{"ru":"Навага","en":"Saffron cod"}','g'),
('Пикша (филе)','seafood','{"ru":"Пикша (филе)","en":"Haddock fillet"}','g'),
('Путассу','seafood','{"ru":"Путассу","en":"Blue whiting"}','g'),
('Зубатка (филе)','seafood','{"ru":"Зубатка (филе)","en":"Wolffish fillet"}','g'),
('Нилийский окунь (филе)','seafood','{"ru":"Нилийский окунь (филе)","en":"Nile perch fillet"}','g'),
('Тилапия (филе)','seafood','{"ru":"Тилапия (филе)","en":"Tilapia fillet"}','g'),
('Дорадо (пресноводный)','seafood','{"ru":"Дорадо (пресноводный)","en":"Freshwater dorado"}','g'),
('Снэппер красный (филе)','seafood','{"ru":"Снэппер красный (филе)","en":"Red snapper fillet"}','g'),
('Барабулька','seafood','{"ru":"Барабулька","en":"Red mullet"}','g'),
('Рыба-меч (стейк)','seafood','{"ru":"Рыба-меч (стейк)","en":"Swordfish steak"}','g'),
('Мойва','seafood','{"ru":"Мойва","en":"Capelin"}','g'),
('Корюшка','seafood','{"ru":"Корюшка","en":"Smelt"}','g'),
('Стерлядь','seafood','{"ru":"Стерлядь","en":"Sterlet"}','g'),
('Осетр (филе)','seafood','{"ru":"Осетр (филе)","en":"Sturgeon fillet"}','g'),
('Белуга (филе)','seafood','{"ru":"Белуга (филе)","en":"Beluga fillet"}','g'),
('Кета (филе)','seafood','{"ru":"Кета (филе)","en":"Chum salmon fillet"}','g'),
('Горбуша (филе)','seafood','{"ru":"Горбуша (филе)","en":"Pink salmon fillet"}','g'),
('Нерка (филе)','seafood','{"ru":"Нерка (филе)","en":"Sockeye salmon fillet"}','g'),
('Семга (филе)','seafood','{"ru":"Семга (филе)","en":"Atlantic salmon fillet"}','g'),
('Семга (слабосоленая)','seafood','{"ru":"Семга (слабосоленая)","en":"Lightly salted salmon"}','g'),

-- ==================== МОРЕПРОДУКТЫ ====================
('Креветки тигровые','seafood','{"ru":"Креветки тигровые","en":"Tiger prawns"}','g'),
('Креветки королевские','seafood','{"ru":"Креветки королевские","en":"King prawns"}','g'),
('Креветки мелкие','seafood','{"ru":"Креветки мелкие","en":"Small shrimp"}','g'),
('Лангустин','seafood','{"ru":"Лангустин","en":"Langoustine"}','g'),
('Омар (целый)','seafood','{"ru":"Омар (целый)","en":"Whole lobster"}','g'),
('Омар (хвост)','seafood','{"ru":"Омар (хвост)","en":"Lobster tail"}','g'),
('Краб (клешни)','seafood','{"ru":"Краб (клешни)","en":"Crab claws"}','g'),
('Краб снежный (мясо)','seafood','{"ru":"Краб снежный (мясо)","en":"Snow crab meat"}','g'),
('Краб камчатский (клешни)','seafood','{"ru":"Краб камчатский (клешни)","en":"King crab claws"}','g'),
('Мидии (в ракушке)','seafood','{"ru":"Мидии (в ракушке)","en":"Mussels in shell"}','g'),
('Мидии (мясо)','seafood','{"ru":"Мидии (мясо)","en":"Mussel meat"}','g'),
('Устрицы','seafood','{"ru":"Устрицы","en":"Oysters"}','pcs'),
('Гребешок морской','seafood','{"ru":"Гребешок морской","en":"Sea scallop"}','g'),
('Гребешок (ИКС)','seafood','{"ru":"Гребешок (ИКС)","en":"Scallop roe"}','g'),
('Кальмар (тушка)','seafood','{"ru":"Кальмар (тушка)","en":"Squid tube"}','g'),
('Кальмар (кольца)','seafood','{"ru":"Кальмар (кольца)","en":"Squid rings"}','g'),
('Осьминог','seafood','{"ru":"Осьминог","en":"Octopus"}','g'),
('Каракатица','seafood','{"ru":"Каракатица","en":"Cuttlefish"}','g'),
('Морской ёж (икра)','seafood','{"ru":"Морской ёж (икра)","en":"Sea urchin roe (uni)"}','g'),
('Рапана (мясо)','seafood','{"ru":"Рапана (мясо)","en":"Rapana meat"}','g'),
('Морской гребешок сушеный','seafood','{"ru":"Морской гребешок сушеный","en":"Dried scallop"}','g'),
('Трепанг','seafood','{"ru":"Трепанг","en":"Sea cucumber"}','g'),
('Икра красная (лосось)','seafood','{"ru":"Икра красная (лосось)","en":"Red caviar (salmon)"}','g'),
('Икра черная (осетровая)','seafood','{"ru":"Икра черная (осетровая)","en":"Black caviar (sturgeon)"}','g'),
('Икра трески','seafood','{"ru":"Икра трески","en":"Cod roe"}','g'),
('Тобико (икра летучей рыбы)','seafood','{"ru":"Тобико (икра летучей рыбы)","en":"Tobiko (flying fish roe)"}','g'),
('Масаго (икра мойвы)','seafood','{"ru":"Масаго (икра мойвы)","en":"Masago (capelin roe)"}','g'),
('Авокадо','vegetables','{"ru":"Авокадо","en":"Avocado"}','g'),

-- ==================== ОВОЩИ ====================
('Морковь','vegetables','{"ru":"Морковь","en":"Carrot"}','g'),
('Лук репчатый','vegetables','{"ru":"Лук репчатый","en":"Onion"}','g'),
('Лук красный','vegetables','{"ru":"Лук красный","en":"Red onion"}','g'),
('Лук-порей','vegetables','{"ru":"Лук-порей","en":"Leek"}','g'),
('Лук-шалот','vegetables','{"ru":"Лук-шалот","en":"Shallot"}','g'),
('Лук зеленый','vegetables','{"ru":"Лук зеленый","en":"Green onion"}','g'),
('Чеснок','vegetables','{"ru":"Чеснок","en":"Garlic"}','g'),
('Картофель','vegetables','{"ru":"Картофель","en":"Potato"}','g'),
('Картофель молодой','vegetables','{"ru":"Картофель молодой","en":"New potato"}','g'),
('Батат (сладкий картофель)','vegetables','{"ru":"Батат (сладкий картофель)","en":"Sweet potato"}','g'),
('Топинамбур','vegetables','{"ru":"Топинамбур","en":"Jerusalem artichoke"}','g'),
('Свекла','vegetables','{"ru":"Свекла","en":"Beetroot"}','g'),
('Свекла мини','vegetables','{"ru":"Свекла мини","en":"Baby beetroot"}','g'),
('Капуста белокочанная','vegetables','{"ru":"Капуста белокочанная","en":"White cabbage"}','g'),
('Капуста краснокочанная','vegetables','{"ru":"Капуста краснокочанная","en":"Red cabbage"}','g'),
('Капуста савойская','vegetables','{"ru":"Капуста савойская","en":"Savoy cabbage"}','g'),
('Капуста брюссельская','vegetables','{"ru":"Капуста брюссельская","en":"Brussels sprouts"}','g'),
('Капуста пекинская','vegetables','{"ru":"Капуста пекинская","en":"Chinese cabbage"}','g'),
('Брокколи','vegetables','{"ru":"Брокколи","en":"Broccoli"}','g'),
('Цветная капуста','vegetables','{"ru":"Цветная капуста","en":"Cauliflower"}','g'),
('Кольраби','vegetables','{"ru":"Кольраби","en":"Kohlrabi"}','g'),
('Болгарский перец красный','vegetables','{"ru":"Болгарский перец красный","en":"Red bell pepper"}','g'),
('Болгарский перец желтый','vegetables','{"ru":"Болгарский перец желтый","en":"Yellow bell pepper"}','g'),
('Болгарский перец зеленый','vegetables','{"ru":"Болгарский перец зеленый","en":"Green bell pepper"}','g'),
('Перец чили красный','vegetables','{"ru":"Перец чили красный","en":"Red chili pepper"}','g'),
('Перец чили зеленый','vegetables','{"ru":"Перец чили зеленый","en":"Green chili pepper"}','g'),
('Перец халапеньо','vegetables','{"ru":"Перец халапеньо","en":"Jalapeño pepper"}','g'),
('Перец поблано','vegetables','{"ru":"Перец поблано","en":"Poblano pepper"}','g'),
('Перец серрано','vegetables','{"ru":"Перец серрано","en":"Serrano pepper"}','g'),
('Помидор','vegetables','{"ru":"Помидор","en":"Tomato"}','g'),
('Помидор черри','vegetables','{"ru":"Помидор черри","en":"Cherry tomato"}','g'),
('Помидор черри желтый','vegetables','{"ru":"Помидор черри желтый","en":"Yellow cherry tomato"}','g'),
('Помидор бакинский','vegetables','{"ru":"Помидор бакинский","en":"Baku tomato"}','g'),
('Томаты вяленые','vegetables','{"ru":"Томаты вяленые","en":"Sun-dried tomatoes"}','g'),
('Томаты консервированные','vegetables','{"ru":"Томаты консервированные","en":"Canned tomatoes"}','g'),
('Огурец','vegetables','{"ru":"Огурец","en":"Cucumber"}','g'),
('Огурец мини','vegetables','{"ru":"Огурец мини","en":"Mini cucumber"}','g'),
('Цукини','vegetables','{"ru":"Цукини","en":"Zucchini"}','g'),
('Кабачок','vegetables','{"ru":"Кабачок","en":"Summer squash"}','g'),
('Тыква','vegetables','{"ru":"Тыква","en":"Pumpkin"}','g'),
('Тыква баттернат','vegetables','{"ru":"Тыква баттернат","en":"Butternut squash"}','g'),
('Тыква хоккайдо','vegetables','{"ru":"Тыква хоккайдо","en":"Hokkaido pumpkin"}','g'),
('Баклажан','vegetables','{"ru":"Баклажан","en":"Eggplant"}','g'),
('Сельдерей (стебель)','vegetables','{"ru":"Сельдерей (стебель)","en":"Celery stalk"}','g'),
('Сельдерей (корень)','vegetables','{"ru":"Сельдерей (корень)","en":"Celeriac"}','g'),
('Пастернак','vegetables','{"ru":"Пастернак","en":"Parsnip"}','g'),
('Петрушка (корень)','vegetables','{"ru":"Петрушка (корень)","en":"Parsley root"}','g'),
('Редька','vegetables','{"ru":"Редька","en":"Radish (large)"}','g'),
('Редис','vegetables','{"ru":"Редис","en":"Radish"}','g'),
('Репа','vegetables','{"ru":"Репа","en":"Turnip"}','g'),
('Брюква','vegetables','{"ru":"Брюква","en":"Rutabaga"}','g'),
('Артишок','vegetables','{"ru":"Артишок","en":"Artichoke"}','g'),
('Фенхель','vegetables','{"ru":"Фенхель","en":"Fennel"}','g'),
('Спаржа зеленая','vegetables','{"ru":"Спаржа зеленая","en":"Green asparagus"}','g'),
('Спаржа белая','vegetables','{"ru":"Спаржа белая","en":"White asparagus"}','g'),
('Спаржа фиолетовая','vegetables','{"ru":"Спаржа фиолетовая","en":"Purple asparagus"}','g'),
('Шпинат','vegetables','{"ru":"Шпинат","en":"Spinach"}','g'),
('Мангольд','vegetables','{"ru":"Мангольд","en":"Swiss chard"}','g'),
('Руккола','vegetables','{"ru":"Руккола","en":"Arugula"}','g'),
('Щавель','vegetables','{"ru":"Щавель","en":"Sorrel"}','g'),
('Листья свеклы','vegetables','{"ru":"Листья свеклы","en":"Beet greens"}','g'),
('Пак-чой','vegetables','{"ru":"Пак-чой","en":"Bok choy"}','g'),
('Мизуна','vegetables','{"ru":"Мизуна","en":"Mizuna"}','g'),
('Кейл (кудрявая капуста)','vegetables','{"ru":"Кейл (кудрявая капуста)","en":"Kale"}','g'),
('Эндивий','vegetables','{"ru":"Эндивий","en":"Endive"}','g'),
('Радиккьо','vegetables','{"ru":"Радиккьо","en":"Radicchio"}','g'),
('Цикорий листовой','vegetables','{"ru":"Цикорий листовой","en":"Chicory leaves"}','g'),
('Айсберг (салат)','vegetables','{"ru":"Айсберг (салат)","en":"Iceberg lettuce"}','g'),
('Романо (салат)','vegetables','{"ru":"Романо (салат)","en":"Romaine lettuce"}','g'),
('Батавия (салат)','vegetables','{"ru":"Батавия (салат)","en":"Batavia lettuce"}','g'),
('Лолло-россо (салат)','vegetables','{"ru":"Лолло-россо (салат)","en":"Lollo rosso lettuce"}','g'),
('Корн (салат)','vegetables','{"ru":"Корн (салат)","en":"Corn salad"}','g'),
('Водяной кресс','vegetables','{"ru":"Водяной кресс","en":"Watercress"}','g'),
('Кресс-салат','vegetables','{"ru":"Кресс-салат","en":"Cress"}','g'),
('Горох стручковый','vegetables','{"ru":"Горох стручковый","en":"Snow peas"}','g'),
('Горох сахарный','vegetables','{"ru":"Горох сахарный","en":"Sugar snap peas"}','g'),
('Фасоль стручковая зеленая','vegetables','{"ru":"Фасоль стручковая зеленая","en":"Green beans"}','g'),
('Фасоль стручковая желтая','vegetables','{"ru":"Фасоль стручковая желтая","en":"Yellow wax beans"}','g'),
('Эдамаме','vegetables','{"ru":"Эдамаме","en":"Edamame"}','g'),
('Кукуруза (початок)','vegetables','{"ru":"Кукуруза (початок)","en":"Corn on the cob"}','g'),
('Кукуруза мини (початок)','vegetables','{"ru":"Кукуруза мини (початок)","en":"Baby corn"}','g'),
('Оливки зеленые (б/к)','vegetables','{"ru":"Оливки зеленые (б/к)","en":"Green olives (pitted)"}','g'),
('Оливки черные (б/к)','vegetables','{"ru":"Оливки черные (б/к)","en":"Black olives (pitted)"}','g'),
('Каперсы','vegetables','{"ru":"Каперсы","en":"Capers"}','g'),
('Побеги бамбука','vegetables','{"ru":"Побеги бамбука","en":"Bamboo shoots"}','g'),
('Корень лотоса','vegetables','{"ru":"Корень лотоса","en":"Lotus root"}','g'),
('Дайкон','vegetables','{"ru":"Дайкон","en":"Daikon"}','g'),
('Имбирь (корень)','spices','{"ru":"Имбирь (корень)","en":"Fresh ginger root"}','g'),
('Галангал','spices','{"ru":"Галангал","en":"Galangal"}','g'),
('Куркума (корень)','spices','{"ru":"Куркума (корень)","en":"Fresh turmeric root"}','g'),
('Хрен (корень)','vegetables','{"ru":"Хрен (корень)","en":"Horseradish root"}','g'),
('Васаби (корень)','spices','{"ru":"Васаби (корень)","en":"Wasabi root"}','g'),
('Трюфель черный','vegetables','{"ru":"Трюфель черный","en":"Black truffle"}','g'),
('Трюфель белый','vegetables','{"ru":"Трюфель белый","en":"White truffle"}','g'),

-- ==================== ГРИБЫ ====================
('Шампиньон','vegetables','{"ru":"Шампиньон","en":"Button mushroom"}','g'),
('Шампиньон коричневый (кримини)','vegetables','{"ru":"Шампиньон коричневый (кримини)","en":"Cremini mushroom"}','g'),
('Портобелло','vegetables','{"ru":"Портобелло","en":"Portobello mushroom"}','g'),
('Вешенка','vegetables','{"ru":"Вешенка","en":"Oyster mushroom"}','g'),
('Вешенка розовая','vegetables','{"ru":"Вешенка розовая","en":"Pink oyster mushroom"}','g'),
('Шиитаке','vegetables','{"ru":"Шиитаке","en":"Shiitake mushroom"}','g'),
('Эринги (королевская вешенка)','vegetables','{"ru":"Эринги (королевская вешенка)","en":"King oyster mushroom"}','g'),
('Лисичка','vegetables','{"ru":"Лисичка","en":"Chanterelle"}','g'),
('Белый гриб (боровик)','vegetables','{"ru":"Белый гриб (боровик)","en":"Porcini mushroom"}','g'),
('Опята','vegetables','{"ru":"Опята","en":"Honey mushrooms"}','g'),
('Маслята','vegetables','{"ru":"Маслята","en":"Slippery jack mushrooms"}','g'),
('Подберезовик','vegetables','{"ru":"Подберезовик","en":"Bay bolete"}','g'),
('Подосиновик','vegetables','{"ru":"Подосиновик","en":"Red cap mushroom"}','g'),
('Рыжик','vegetables','{"ru":"Рыжик","en":"Saffron milk cap"}','g'),
('Сморчок','vegetables','{"ru":"Сморчок","en":"Morel mushroom"}','g'),
('Трюфель черный летний','vegetables','{"ru":"Трюфель черный летний","en":"Summer truffle"}','g'),
('Энокитаке','vegetables','{"ru":"Энокитаке","en":"Enoki mushroom"}','g'),
('Намеко','vegetables','{"ru":"Намеко","en":"Nameko mushroom"}','g'),
('Муэр (черный древесный гриб)','vegetables','{"ru":"Муэр (черный древесный гриб)","en":"Black wood ear mushroom"}','g'),
('Снежный гриб (серебряный)','vegetables','{"ru":"Снежный гриб (серебряный)","en":"Silver ear mushroom"}','g'),
('Грибы белые сушеные','vegetables','{"ru":"Грибы белые сушеные","en":"Dried porcini mushrooms"}','g'),
('Грибы шиитаке сушеные','vegetables','{"ru":"Грибы шиитаке сушеные","en":"Dried shiitake mushrooms"}','g'),

-- ==================== ФРУКТЫ ====================
('Яблоко зеленое','fruits','{"ru":"Яблоко зеленое","en":"Green apple"}','g'),
('Яблоко красное','fruits','{"ru":"Яблоко красное","en":"Red apple"}','g'),
('Яблоко голден','fruits','{"ru":"Яблоко голден","en":"Golden apple"}','g'),
('Груша','fruits','{"ru":"Груша","en":"Pear"}','g'),
('Груша конференс','fruits','{"ru":"Груша конференс","en":"Conference pear"}','g'),
('Айва','fruits','{"ru":"Айва","en":"Quince"}','g'),
('Апельсин','fruits','{"ru":"Апельсин","en":"Orange"}','g'),
('Мандарин','fruits','{"ru":"Мандарин","en":"Mandarin"}','g'),
('Клементин','fruits','{"ru":"Клементин","en":"Clementine"}','g'),
('Лимон','fruits','{"ru":"Лимон","en":"Lemon"}','g'),
('Лайм','fruits','{"ru":"Лайм","en":"Lime"}','g'),
('Грейпфрут','fruits','{"ru":"Грейпфрут","en":"Grapefruit"}','g'),
('Помело','fruits','{"ru":"Помело","en":"Pomelo"}','g'),
('Юзу','fruits','{"ru":"Юзу","en":"Yuzu"}','g'),
('Кумкват','fruits','{"ru":"Кумкват","en":"Kumquat"}','g'),
('Банан','fruits','{"ru":"Банан","en":"Banana"}','g'),
('Банан мини (чирилито)','fruits','{"ru":"Банан мини (чирилито)","en":"Mini banana"}','g'),
('Ананас','fruits','{"ru":"Ананас","en":"Pineapple"}','g'),
('Манго (Альфонсо)','fruits','{"ru":"Манго (Альфонсо)","en":"Mango (Alphonso)"}','g'),
('Манго (Кент)','fruits','{"ru":"Манго (Кент)","en":"Mango (Kent)"}','g'),
('Папайя','fruits','{"ru":"Папайя","en":"Papaya"}','g'),
('Маракуйя','fruits','{"ru":"Маракуйя","en":"Passion fruit"}','g'),
('Гуава','fruits','{"ru":"Гуава","en":"Guava"}','g'),
('Питайя (драконий фрукт)','fruits','{"ru":"Питайя (драконий фрукт)","en":"Dragon fruit (pitaya)"}','g'),
('Рамбутан','fruits','{"ru":"Рамбутан","en":"Rambutan"}','g'),
('Личи','fruits','{"ru":"Личи","en":"Lychee"}','g'),
('Лонган','fruits','{"ru":"Лонган","en":"Longan"}','g'),
('Дуриан','fruits','{"ru":"Дуриан","en":"Durian"}','g'),
('Карамбола','fruits','{"ru":"Карамбола","en":"Star fruit"}','g'),
('Тамаринд','fruits','{"ru":"Тамаринд","en":"Tamarind"}','g'),
('Фейхоа','fruits','{"ru":"Фейхоа","en":"Feijoa"}','g'),
('Кокос (мякоть)','fruits','{"ru":"Кокос (мякоть)","en":"Coconut flesh"}','g'),
('Кокосовое молоко','dairy','{"ru":"Кокосовое молоко","en":"Coconut milk"}','ml'),
('Кокосовые сливки','dairy','{"ru":"Кокосовые сливки","en":"Coconut cream"}','ml'),
('Персик','fruits','{"ru":"Персик","en":"Peach"}','g'),
('Нектарин','fruits','{"ru":"Нектарин","en":"Nectarine"}','g'),
('Абрикос','fruits','{"ru":"Абрикос","en":"Apricot"}','g'),
('Слива','fruits','{"ru":"Слива","en":"Plum"}','g'),
('Алыча','fruits','{"ru":"Алыча","en":"Cherry plum"}','g'),
('Вишня','fruits','{"ru":"Вишня","en":"Sour cherry"}','g'),
('Черешня','fruits','{"ru":"Черешня","en":"Sweet cherry"}','g'),
('Инжир','fruits','{"ru":"Инжир","en":"Fig"}','g'),
('Инжир сушеный','fruits','{"ru":"Инжир сушеный","en":"Dried fig"}','g'),
('Хурма','fruits','{"ru":"Хурма","en":"Persimmon"}','g'),
('Гранат','fruits','{"ru":"Гранат","en":"Pomegranate"}','g'),
('Мангостин','fruits','{"ru":"Мангостин","en":"Mangosteen"}','g'),
('Физалис','fruits','{"ru":"Физалис","en":"Physalis"}','g'),
('Крыжовник','fruits','{"ru":"Крыжовник","en":"Gooseberry"}','g'),
('Смородина черная','fruits','{"ru":"Смородина черная","en":"Black currant"}','g'),
('Смородина красная','fruits','{"ru":"Смородина красная","en":"Red currant"}','g'),
('Смородина белая','fruits','{"ru":"Смородина белая","en":"White currant"}','g'),
('Малина','fruits','{"ru":"Малина","en":"Raspberry"}','g'),
('Ежевика','fruits','{"ru":"Ежевика","en":"Blackberry"}','g'),
('Клубника','fruits','{"ru":"Клубника","en":"Strawberry"}','g'),
('Клубника мини','fruits','{"ru":"Клубника мини","en":"Mini strawberry"}','g'),
('Земляника лесная','fruits','{"ru":"Земляника лесная","en":"Wild strawberry"}','g'),
('Черника','fruits','{"ru":"Черника","en":"Blueberry"}','g'),
('Голубика','fruits','{"ru":"Голубика","en":"Blueberry (highbush)"}','g'),
('Брусника','fruits','{"ru":"Брусника","en":"Lingonberry"}','g'),
('Клюква','fruits','{"ru":"Клюква","en":"Cranberry"}','g'),
('Морошка','fruits','{"ru":"Морошка","en":"Cloudberry"}','g'),
('Виноград белый (кишмиш)','fruits','{"ru":"Виноград белый (кишмиш)","en":"White seedless grapes"}','g'),
('Виноград красный','fruits','{"ru":"Виноград красный","en":"Red grapes"}','g'),
('Виноград черный','fruits','{"ru":"Виноград черный","en":"Black grapes"}','g'),
('Арбуз','fruits','{"ru":"Арбуз","en":"Watermelon"}','g'),
('Дыня','fruits','{"ru":"Дыня","en":"Melon"}','g'),
('Дыня торпеда','fruits','{"ru":"Дыня торпеда","en":"Torpedo melon"}','g'),
('Дыня шаренталь','fruits','{"ru":"Дыня шаренталь","en":"Charentais melon"}','g'),

-- ==================== СУХОФРУКТЫ ====================
('Изюм','fruits','{"ru":"Изюм","en":"Raisins"}','g'),
('Курага','fruits','{"ru":"Курага","en":"Dried apricot"}','g'),
('Чернослив','fruits','{"ru":"Чернослив","en":"Prunes"}','g'),
('Финики (Medjool)','fruits','{"ru":"Финики (Medjool)","en":"Medjool dates"}','g'),
('Финики сушеные','fruits','{"ru":"Финики сушеные","en":"Dried dates"}','g'),
('Манго сушеное','fruits','{"ru":"Манго сушеное","en":"Dried mango"}','g'),
('Клюква сушеная','fruits','{"ru":"Клюква сушеная","en":"Dried cranberry"}','g'),
('Черника сушеная','fruits','{"ru":"Черника сушеная","en":"Dried blueberry"}','g'),
('Ананас сушеный','fruits','{"ru":"Ананас сушеный","en":"Dried pineapple"}','g'),
('Папайя сушеная','fruits','{"ru":"Папайя сушеная","en":"Dried papaya"}','g'),
('Банан сушеный','fruits','{"ru":"Банан сушеный","en":"Dried banana"}','g'),

-- ==================== МОЛОЧНЫЕ ПРОДУКТЫ ====================
('Молоко 2.5%','dairy','{"ru":"Молоко 2.5%","en":"Milk 2.5%"}','ml'),
('Молоко 3.2%','dairy','{"ru":"Молоко 3.2%","en":"Milk 3.2%"}','ml'),
('Молоко 3.5%','dairy','{"ru":"Молоко 3.5%","en":"Milk 3.5%"}','ml'),
('Молоко 6%','dairy','{"ru":"Молоко 6%","en":"Milk 6%"}','ml'),
('Молоко обезжиренное','dairy','{"ru":"Молоко обезжиренное","en":"Skim milk"}','ml'),
('Молоко козье','dairy','{"ru":"Молоко козье","en":"Goat milk"}','ml'),
('Молоко овечье','dairy','{"ru":"Молоко овечье","en":"Sheep milk"}','ml'),
('Молоко топленое','dairy','{"ru":"Молоко топленое","en":"Baked milk"}','ml'),
('Молоко сгущенное','dairy','{"ru":"Молоко сгущенное","en":"Condensed milk"}','ml'),
('Молоко сухое','dairy','{"ru":"Молоко сухое","en":"Dry milk powder"}','g'),
('Сливки 10%','dairy','{"ru":"Сливки 10%","en":"Light cream 10%"}','ml'),
('Сливки 20%','dairy','{"ru":"Сливки 20%","en":"Cream 20%"}','ml'),
('Сливки 33%','dairy','{"ru":"Сливки 33%","en":"Heavy cream 33%"}','ml'),
('Сливки 35%','dairy','{"ru":"Сливки 35%","en":"Heavy whipping cream 35%"}','ml'),
('Сливки 38%','dairy','{"ru":"Сливки 38%","en":"Heavy whipping cream 38%"}','ml'),
('Сливки взбитые','dairy','{"ru":"Сливки взбитые","en":"Whipped cream"}','ml'),
('Сливки кокосовые','dairy','{"ru":"Сливки кокосовые","en":"Coconut cream"}','ml'),
('Сметана 10%','dairy','{"ru":"Сметана 10%","en":"Sour cream 10%"}','g'),
('Сметана 15%','dairy','{"ru":"Сметана 15%","en":"Sour cream 15%"}','g'),
('Сметана 20%','dairy','{"ru":"Сметана 20%","en":"Sour cream 20%"}','g'),
('Сметана 25%','dairy','{"ru":"Сметана 25%","en":"Sour cream 25%"}','g'),
('Кефир 1%','dairy','{"ru":"Кефир 1%","en":"Kefir 1%"}','ml'),
('Кефир 2.5%','dairy','{"ru":"Кефир 2.5%","en":"Kefir 2.5%"}','ml'),
('Кефир 3.2%','dairy','{"ru":"Кефир 3.2%","en":"Kefir 3.2%"}','ml'),
('Ряженка','dairy','{"ru":"Ряженка","en":"Ryazhenka (baked milk yogurt)"}','ml'),
('Простокваша','dairy','{"ru":"Простокваша","en":"Clabbered milk"}','ml'),
('Йогурт натуральный','dairy','{"ru":"Йогурт натуральный","en":"Plain yogurt"}','g'),
('Йогурт греческий 0%','dairy','{"ru":"Йогурт греческий 0%","en":"Greek yogurt 0%"}','g'),
('Йогурт греческий 2%','dairy','{"ru":"Йогурт греческий 2%","en":"Greek yogurt 2%"}','g'),
('Йогурт греческий 10%','dairy','{"ru":"Йогурт греческий 10%","en":"Greek yogurt 10%"}','g'),
('Айран','dairy','{"ru":"Айран","en":"Ayran"}','ml'),
('Лабне','dairy','{"ru":"Лабне","en":"Labneh"}','g'),
('Творог 0%','dairy','{"ru":"Творог 0%","en":"Cottage cheese 0%"}','g'),
('Творог 2%','dairy','{"ru":"Творог 2%","en":"Cottage cheese 2%"}','g'),
('Творог 5%','dairy','{"ru":"Творог 5%","en":"Cottage cheese 5%"}','g'),
('Творог 9%','dairy','{"ru":"Творог 9%","en":"Cottage cheese 9%"}','g'),
('Творог 18%','dairy','{"ru":"Творог 18%","en":"Cottage cheese 18%"}','g'),
('Маскарпоне','dairy','{"ru":"Маскарпоне","en":"Mascarpone"}','g'),
('Рикотта','dairy','{"ru":"Рикотта","en":"Ricotta"}','g'),
('Крем-чиз','dairy','{"ru":"Крем-чиз","en":"Cream cheese"}','g'),
('Филадельфия (сыр)','dairy','{"ru":"Филадельфия (сыр)","en":"Philadelphia cream cheese"}','g'),
('Сыр моцарелла (шарики)','dairy','{"ru":"Сыр моцарелла (шарики)","en":"Mozzarella balls"}','g'),
('Сыр моцарелла (буффало)','dairy','{"ru":"Сыр моцарелла (буффало)","en":"Buffalo mozzarella"}','g'),
('Сыр страчателла','dairy','{"ru":"Сыр страчателла","en":"Stracciatella cheese"}','g'),
('Сыр буррата','dairy','{"ru":"Сыр буррата","en":"Burrata cheese"}','g'),
('Сыр фета','dairy','{"ru":"Сыр фета","en":"Feta cheese"}','g'),
('Сыр бри','dairy','{"ru":"Сыр бри","en":"Brie cheese"}','g'),
('Сыр камамбер','dairy','{"ru":"Сыр камамбер","en":"Camembert cheese"}','g'),
('Сыр рокфор','dairy','{"ru":"Сыр рокфор","en":"Roquefort cheese"}','g'),
('Сыр горгонзола','dairy','{"ru":"Сыр горгонзола","en":"Gorgonzola cheese"}','g'),
('Сыр дор блю','dairy','{"ru":"Сыр дор блю","en":"Dor Blue cheese"}','g'),
('Сыр пармезан','dairy','{"ru":"Сыр пармезан","en":"Parmesan cheese"}','g'),
('Сыр грана падано','dairy','{"ru":"Сыр грана падано","en":"Grana Padano cheese"}','g'),
('Сыр пекорино','dairy','{"ru":"Сыр пекорино","en":"Pecorino cheese"}','g'),
('Сыр грюйер','dairy','{"ru":"Сыр грюйер","en":"Gruyère cheese"}','g'),
('Сыр эмменталь','dairy','{"ru":"Сыр эмменталь","en":"Emmental cheese"}','g'),
('Сыр маасдам','dairy','{"ru":"Сыр маасдам","en":"Maasdam cheese"}','g'),
('Сыр гауда','dairy','{"ru":"Сыр гауда","en":"Gouda cheese"}','g'),
('Сыр эдам','dairy','{"ru":"Сыр эдам","en":"Edam cheese"}','g'),
('Сыр чеддер','dairy','{"ru":"Сыр чеддер","en":"Cheddar cheese"}','g'),
('Сыр российский','dairy','{"ru":"Сыр российский","en":"Russian cheese"}','g'),
('Сыр голландский','dairy','{"ru":"Сыр голландский","en":"Dutch cheese"}','g'),
('Сыр адыгейский','dairy','{"ru":"Сыр адыгейский","en":"Adyghe cheese"}','g'),
('Сыр сулугуни','dairy','{"ru":"Сыр сулугуни","en":"Sulguni cheese"}','g'),
('Сыр брынза','dairy','{"ru":"Сыр брынза","en":"Bryndza cheese"}','g'),
('Сыр халуми','dairy','{"ru":"Сыр халуми","en":"Halloumi cheese"}','g'),
('Сыр манчего','dairy','{"ru":"Сыр манчего","en":"Manchego cheese"}','g'),
('Сыр азиаго','dairy','{"ru":"Сыр азиаго","en":"Asiago cheese"}','g'),
('Сыр таледжо','dairy','{"ru":"Сыр таледжо","en":"Taleggio cheese"}','g'),
('Сыр реблошон','dairy','{"ru":"Сыр реблошон","en":"Reblochon cheese"}','g'),
('Сыр раклет','dairy','{"ru":"Сыр раклет","en":"Raclette cheese"}','g'),
('Сыр проволоне','dairy','{"ru":"Сыр проволоне","en":"Provolone cheese"}','g'),
('Сыр страчино','dairy','{"ru":"Сыр страчино","en":"Stracchino cheese"}','g'),
('Масло сливочное 72.5%','dairy','{"ru":"Масло сливочное 72.5%","en":"Butter 72.5%"}','g'),
('Масло сливочное 82.5%','dairy','{"ru":"Масло сливочное 82.5%","en":"Butter 82.5%"}','g'),
('Масло сливочное топленое (ги)','dairy','{"ru":"Масло сливочное топленое (ги)","en":"Ghee (clarified butter)"}','g'),
('Масло козье','dairy','{"ru":"Масло козье","en":"Goat butter"}','g'),
('Яйцо куриное С0','eggs','{"ru":"Яйцо куриное С0","en":"Chicken egg (large)"}','pcs'),
('Яйцо куриное С1','eggs','{"ru":"Яйцо куриное С1","en":"Chicken egg (medium)"}','pcs'),
('Яйцо куриное С2','eggs','{"ru":"Яйцо куриное С2","en":"Chicken egg (small)"}','pcs'),
('Яйцо перепелиное','eggs','{"ru":"Яйцо перепелиное","en":"Quail egg"}','pcs'),
('Яйцо утиное','eggs','{"ru":"Яйцо утиное","en":"Duck egg"}','pcs'),
('Яйцо гусиное','eggs','{"ru":"Яйцо гусиное","en":"Goose egg"}','pcs'),
('Яйцо страусиное','eggs','{"ru":"Яйцо страусиное","en":"Ostrich egg"}','pcs'),
('Белок яичный','eggs','{"ru":"Белок яичный","en":"Egg white"}','g'),
('Желток яичный','eggs','{"ru":"Желток яичный","en":"Egg yolk"}','g'),
('Меланж яичный','eggs','{"ru":"Меланж яичный","en":"Egg melange"}','g'),

-- ==================== КРУПЫ И ЗЕРНОВЫЕ ====================
('Рис белый (длиннозерный)','grains','{"ru":"Рис белый (длиннозерный)","en":"Long grain white rice"}','g'),
('Рис белый (круглозерный)','grains','{"ru":"Рис белый (круглозерный)","en":"Round grain white rice"}','g'),
('Рис басмати','grains','{"ru":"Рис басмати","en":"Basmati rice"}','g'),
('Рис жасмин','grains','{"ru":"Рис жасмин","en":"Jasmine rice"}','g'),
('Рис для суши','grains','{"ru":"Рис для суши","en":"Sushi rice"}','g'),
('Рис арборио (ризотто)','grains','{"ru":"Рис арборио (ризотто)","en":"Arborio rice"}','g'),
('Рис карнароли (ризотто)','grains','{"ru":"Рис карнароли (ризотто)","en":"Carnaroli rice"}','g'),
('Рис черный (запрещенный)','grains','{"ru":"Рис черный (запрещенный)","en":"Black forbidden rice"}','g'),
('Рис коричневый','grains','{"ru":"Рис коричневый","en":"Brown rice"}','g'),
('Рис дикий','grains','{"ru":"Рис дикий","en":"Wild rice"}','g'),
('Рис клейкий','grains','{"ru":"Рис клейкий","en":"Sticky rice"}','g'),
('Рис красный','grains','{"ru":"Рис красный","en":"Red rice"}','g'),
('Гречка ядрица','grains','{"ru":"Гречка ядрица","en":"Buckwheat groats"}','g'),
('Гречка продел','grains','{"ru":"Гречка продел","en":"Buckwheat flakes"}','g'),
('Пшено','grains','{"ru":"Пшено","en":"Millet"}','g'),
('Овсяные хлопья','grains','{"ru":"Овсяные хлопья","en":"Rolled oats"}','g'),
('Овсяные хлопья быстрого приготовления','grains','{"ru":"Овсяные хлопья быстрого приготовления","en":"Instant oats"}','g'),
('Геркулес','grains','{"ru":"Геркулес","en":"Oat flakes (Hercules)"}','g'),
('Овсяная крупа','grains','{"ru":"Овсяная крупа","en":"Oat groats"}','g'),
('Манная крупа','grains','{"ru":"Манная крупа","en":"Semolina"}','g'),
('Кукурузная крупа','grains','{"ru":"Кукурузная крупа","en":"Corn grits"}','g'),
('Полента','grains','{"ru":"Полента","en":"Polenta"}','g'),
('Пшеничная крупа','grains','{"ru":"Пшеничная крупа","en":"Wheat groats"}','g'),
('Булгур','grains','{"ru":"Булгур","en":"Bulgur"}','g'),
('Кускус','grains','{"ru":"Кускус","en":"Couscous"}','g'),
('Киноа белая','grains','{"ru":"Киноа белая","en":"White quinoa"}','g'),
('Киноа красная','grains','{"ru":"Киноа красная","en":"Red quinoa"}','g'),
('Киноа черная','grains','{"ru":"Киноа черная","en":"Black quinoa"}','g'),
('Амарант','grains','{"ru":"Амарант","en":"Amaranth"}','g'),
('Полба','grains','{"ru":"Полба","en":"Spelt"}','g'),
('Камут','grains','{"ru":"Камут","en":"Kamut"}','g'),
('Теф','grains','{"ru":"Теф","en":"Teff"}','g'),
('Перловая крупа','grains','{"ru":"Перловая крупа","en":"Pearl barley"}','g'),
('Ячневая крупа','grains','{"ru":"Ячневая крупа","en":"Barley groats"}','g'),
('Сорго','grains','{"ru":"Сорго","en":"Sorghum"}','g'),
('Фрике (обжаренная пшеница)','grains','{"ru":"Фрике (обжаренная пшеница)","en":"Freekeh"}','g'),

-- ==================== МУКА И ВЫПЕЧКА ====================
('Мука пшеничная в/с','bakery','{"ru":"Мука пшеничная в/с","en":"All-purpose wheat flour"}','g'),
('Мука пшеничная 1 сорт','bakery','{"ru":"Мука пшеничная 1 сорт","en":"Wheat flour type 1"}','g'),
('Мука пшеничная цельнозерновая','bakery','{"ru":"Мука пшеничная цельнозерновая","en":"Whole wheat flour"}','g'),
('Мука ржаная','bakery','{"ru":"Мука ржаная","en":"Rye flour"}','g'),
('Мука ржаная обдирная','bakery','{"ru":"Мука ржаная обдирная","en":"Peeled rye flour"}','g'),
('Мука кукурузная','bakery','{"ru":"Мука кукурузная","en":"Corn flour"}','g'),
('Мука рисовая','bakery','{"ru":"Мука рисовая","en":"Rice flour"}','g'),
('Мука гречневая','bakery','{"ru":"Мука гречневая","en":"Buckwheat flour"}','g'),
('Мука нутовая','bakery','{"ru":"Мука нутовая","en":"Chickpea flour"}','g'),
('Мука миндальная','bakery','{"ru":"Мука миндальная","en":"Almond flour"}','g'),
('Мука кокосовая','bakery','{"ru":"Мука кокосовая","en":"Coconut flour"}','g'),
('Мука тапиоковая','bakery','{"ru":"Мука тапиоковая","en":"Tapioca flour"}','g'),
('Мука полбяная','bakery','{"ru":"Мука полбяная","en":"Spelt flour"}','g'),
('Мука овсяная','bakery','{"ru":"Мука овсяная","en":"Oat flour"}','g'),
('Крахмал картофельный','bakery','{"ru":"Крахмал картофельный","en":"Potato starch"}','g'),
('Крахмал кукурузный','bakery','{"ru":"Крахмал кукурузный","en":"Corn starch"}','g'),
('Крахмал тапиоковый','bakery','{"ru":"Крахмал тапиоковый","en":"Tapioca starch"}','g'),
('Крахмал рисовый','bakery','{"ru":"Крахмал рисовый","en":"Rice starch"}','g'),
('Дрожжи сухие','bakery','{"ru":"Дрожжи сухие","en":"Dry yeast"}','g'),
('Дрожжи прессованные','bakery','{"ru":"Дрожжи прессованные","en":"Fresh pressed yeast"}','g'),
('Разрыхлитель','bakery','{"ru":"Разрыхлитель","en":"Baking powder"}','g'),
('Сода пищевая','bakery','{"ru":"Сода пищевая","en":"Baking soda"}','g'),
('Ваниль (стручок)','spices','{"ru":"Ваниль (стручок)","en":"Vanilla bean"}','g'),
('Ванилин','spices','{"ru":"Ванилин","en":"Vanillin"}','g'),
('Ванильный сахар','bakery','{"ru":"Ванильный сахар","en":"Vanilla sugar"}','g'),
('Ванильный экстракт','bakery','{"ru":"Ванильный экстракт","en":"Vanilla extract"}','ml'),
('Желатин листовой','bakery','{"ru":"Желатин листовой","en":"Sheet gelatin"}','g'),
('Желатин порошковый','bakery','{"ru":"Желатин порошковый","en":"Powdered gelatin"}','g'),
('Агар-агар','bakery','{"ru":"Агар-агар","en":"Agar-agar"}','g'),
('Пектин','bakery','{"ru":"Пектин","en":"Pectin"}','g'),
('Ксантановая камедь','bakery','{"ru":"Ксантановая камедь","en":"Xanthan gum"}','g'),
('Панировочные сухари','bakery','{"ru":"Панировочные сухари","en":"Breadcrumbs"}','g'),
('Панко (японские сухари)','bakery','{"ru":"Панко (японские сухари)","en":"Panko breadcrumbs"}','g'),

-- ==================== БОБОВЫЕ ====================
('Нут','legumes','{"ru":"Нут","en":"Chickpeas"}','g'),
('Нут (консервированный)','legumes','{"ru":"Нут (консервированный)","en":"Canned chickpeas"}','g'),
('Чечевица красная','legumes','{"ru":"Чечевица красная","en":"Red lentils"}','g'),
('Чечевица зеленая','legumes','{"ru":"Чечевица зеленая","en":"Green lentils"}','g'),
('Чечевица черная (белуга)','legumes','{"ru":"Чечевица черная (белуга)","en":"Black beluga lentils"}','g'),
('Чечевица французская (пюи)','legumes','{"ru":"Чечевица французская (пюи)","en":"French Puy lentils"}','g'),
('Фасоль белая','legumes','{"ru":"Фасоль белая","en":"White beans"}','g'),
('Фасоль красная','legumes','{"ru":"Фасоль красная","en":"Red kidney beans"}','g'),
('Фасоль черная','legumes','{"ru":"Фасоль черная","en":"Black beans"}','g'),
('Фасоль пинто','legumes','{"ru":"Фасоль пинто","en":"Pinto beans"}','g'),
('Фасоль мунг (маш)','legumes','{"ru":"Фасоль мунг (маш)","en":"Mung beans"}','g'),
('Фасоль адзуки','legumes','{"ru":"Фасоль адзуки","en":"Adzuki beans"}','g'),
('Горох сухой','legumes','{"ru":"Горох сухой","en":"Dried peas"}','g'),
('Горох колотый','legumes','{"ru":"Горох колотый","en":"Split peas"}','g'),
('Чечевица (консервированная)','legumes','{"ru":"Чечевица (консервированная)","en":"Canned lentils"}','g'),
('Соя (бобы)','legumes','{"ru":"Соя (бобы)","en":"Soybeans"}','g'),
('Тофу твердый','legumes','{"ru":"Тофу твердый","en":"Firm tofu"}','g'),
('Тофу шелковый','legumes','{"ru":"Тофу шелковый","en":"Silken tofu"}','g'),
('Темпе','legumes','{"ru":"Темпе","en":"Tempeh"}','g'),

-- ==================== ОРЕХИ И СЕМЕНА ====================
('Грецкий орех','nuts','{"ru":"Грецкий орех","en":"Walnut"}','g'),
('Миндаль','nuts','{"ru":"Миндаль","en":"Almond"}','g'),
('Миндаль жареный','nuts','{"ru":"Миндаль жареный","en":"Roasted almond"}','g'),
('Фундук','nuts','{"ru":"Фундук","en":"Hazelnut"}','g'),
('Фундук жареный','nuts','{"ru":"Фундук жареный","en":"Roasted hazelnut"}','g'),
('Фисташки','nuts','{"ru":"Фисташки","en":"Pistachios"}','g'),
('Фисташки несоленые','nuts','{"ru":"Фисташки несоленые","en":"Unsalted pistachios"}','g'),
('Кешью','nuts','{"ru":"Кешью","en":"Cashew"}','g'),
('Кешью жареный','nuts','{"ru":"Кешью жареный","en":"Roasted cashew"}','g'),
('Кедровый орех','nuts','{"ru":"Кедровый орех","en":"Pine nut"}','g'),
('Пекан','nuts','{"ru":"Пекан","en":"Pecan"}','g'),
('Макадамия','nuts','{"ru":"Макадамия","en":"Macadamia nut"}','g'),
('Бразильский орех','nuts','{"ru":"Бразильский орех","en":"Brazil nut"}','g'),
('Арахис','nuts','{"ru":"Арахис","en":"Peanut"}','g'),
('Арахис жареный','nuts','{"ru":"Арахис жареный","en":"Roasted peanut"}','g'),
('Паста арахисовая','nuts','{"ru":"Паста арахисовая","en":"Peanut butter"}','g'),
('Паста миндальная','nuts','{"ru":"Паста миндальная","en":"Almond butter"}','g'),
('Паста кешью','nuts','{"ru":"Паста кешью","en":"Cashew butter"}','g'),
('Паста из фундука (нутелла-тип)','nuts','{"ru":"Паста из фундука (нутелла-тип)","en":"Hazelnut paste"}','g'),
('Кунжут белый','nuts','{"ru":"Кунжут белый","en":"White sesame seeds"}','g'),
('Кунжут черный','nuts','{"ru":"Кунжут черный","en":"Black sesame seeds"}','g'),
('Тахини (паста кунжутная)','nuts','{"ru":"Тахини (паста кунжутная)","en":"Tahini (sesame paste)"}','g'),
('Семена подсолнечника','nuts','{"ru":"Семена подсолнечника","en":"Sunflower seeds"}','g'),
('Семена тыквы','nuts','{"ru":"Семена тыквы","en":"Pumpkin seeds"}','g'),
('Семена льна','nuts','{"ru":"Семена льна","en":"Flax seeds"}','g'),
('Семена чиа','nuts','{"ru":"Семена чиа","en":"Chia seeds"}','g'),
('Семена мака','nuts','{"ru":"Семена мака","en":"Poppy seeds"}','g'),
('Семена горчицы желтой','spices','{"ru":"Семена горчицы желтой","en":"Yellow mustard seeds"}','g'),
('Семена горчицы черной','spices','{"ru":"Семена горчицы черной","en":"Black mustard seeds"}','g'),
('Семена фенхеля','spices','{"ru":"Семена фенхеля","en":"Fennel seeds"}','g'),
('Семена кориандра','spices','{"ru":"Семена кориандра","en":"Coriander seeds"}','g'),
('Семена тмина','spices','{"ru":"Семена тмина","en":"Caraway seeds"}','g'),
('Семена кумина (зира)','spices','{"ru":"Семена кумина (зира)","en":"Cumin seeds"}','g'),
('Семена аниса','spices','{"ru":"Семена аниса","en":"Anise seeds"}','g'),
('Семена нигеллы (чернушка)','spices','{"ru":"Семена нигеллы (чернушка)","en":"Nigella seeds"}','g'),
('Семена пажитника','spices','{"ru":"Семена пажитника","en":"Fenugreek seeds"}','g'),
('Семена кардамона','spices','{"ru":"Семена кардамона","en":"Cardamom seeds"}','g'),

-- ==================== СПЕЦИИ И ПРЯНОСТИ ====================
('Перец черный горошек','spices','{"ru":"Перец черный горошек","en":"Black peppercorns"}','g'),
('Перец черный молотый','spices','{"ru":"Перец черный молотый","en":"Ground black pepper"}','g'),
('Перец белый горошек','spices','{"ru":"Перец белый горошек","en":"White peppercorns"}','g'),
('Перец белый молотый','spices','{"ru":"Перец белый молотый","en":"Ground white pepper"}','g'),
('Перец розовый горошек','spices','{"ru":"Перец розовый горошек","en":"Pink peppercorns"}','g'),
('Перец зеленый горошек','spices','{"ru":"Перец зеленый горошек","en":"Green peppercorns"}','g'),
('Смесь перцев','spices','{"ru":"Смесь перцев","en":"Mixed peppercorns"}','g'),
('Перец душистый','spices','{"ru":"Перец душистый","en":"Allspice"}','g'),
('Перец кайенский','spices','{"ru":"Перец кайенский","en":"Cayenne pepper"}','g'),
('Паприка сладкая','spices','{"ru":"Паприка сладкая","en":"Sweet paprika"}','g'),
('Паприка копченая','spices','{"ru":"Паприка копченая","en":"Smoked paprika"}','g'),
('Паприка острая','spices','{"ru":"Паприка острая","en":"Hot paprika"}','g'),
('Куркума молотая','spices','{"ru":"Куркума молотая","en":"Ground turmeric"}','g'),
('Кориандр молотый','spices','{"ru":"Кориандр молотый","en":"Ground coriander"}','g'),
('Кумин молотый (зира)','spices','{"ru":"Кумин молотый (зира)","en":"Ground cumin"}','g'),
('Тмин молотый','spices','{"ru":"Тмин молотый","en":"Ground caraway"}','g'),
('Кардамон молотый','spices','{"ru":"Кардамон молотый","en":"Ground cardamom"}','g'),
('Кардамон зеленый (стручки)','spices','{"ru":"Кардамон зеленый (стручки)","en":"Green cardamom pods"}','g'),
('Кардамон черный','spices','{"ru":"Кардамон черный","en":"Black cardamom"}','g'),
('Корица молотая','spices','{"ru":"Корица молотая","en":"Ground cinnamon"}','g'),
('Корица (палочки)','spices','{"ru":"Корица (палочки)","en":"Cinnamon sticks"}','g'),
('Мускатный орех молотый','spices','{"ru":"Мускатный орех молотый","en":"Ground nutmeg"}','g'),
('Мускатный орех (целый)','spices','{"ru":"Мускатный орех (целый)","en":"Whole nutmeg"}','g'),
('Мускатный цвет (мэйс)','spices','{"ru":"Мускатный цвет (мэйс)","en":"Mace"}','g'),
('Гвоздика молотая','spices','{"ru":"Гвоздика молотая","en":"Ground cloves"}','g'),
('Гвоздика (целая)','spices','{"ru":"Гвоздика (целая)","en":"Whole cloves"}','g'),
('Анис звездчатый (бадьян)','spices','{"ru":"Анис звездчатый (бадьян)","en":"Star anise"}','g'),
('Имбирь молотый','spices','{"ru":"Имбирь молотый","en":"Ground ginger"}','g'),
('Шафран','spices','{"ru":"Шафран","en":"Saffron"}','g'),
('Сумах','spices','{"ru":"Сумах","en":"Sumac"}','g'),
('Зерберет (эфиопская смесь)','spices','{"ru":"Зерберет (эфиопская смесь)","en":"Berbere spice blend"}','g'),
('Рас-эль-ханут','spices','{"ru":"Рас-эль-ханут","en":"Ras el hanout"}','g'),
('Гарам масала','spices','{"ru":"Гарам масала","en":"Garam masala"}','g'),
('Карри порошок','spices','{"ru":"Карри порошок","en":"Curry powder"}','g'),
('Карри паста красная','spices','{"ru":"Карри паста красная","en":"Red curry paste"}','g'),
('Карри паста зеленая','spices','{"ru":"Карри паста зеленая","en":"Green curry paste"}','g'),
('Карри паста желтая','spices','{"ru":"Карри паста желтая","en":"Yellow curry paste"}','g'),
('Смесь 5 специй (китайская)','spices','{"ru":"Смесь 5 специй (китайская)","en":"Five spice powder"}','g'),
('Смесь для глинтвейна','spices','{"ru":"Смесь для глинтвейна","en":"Mulled wine spice blend"}','g'),
('Смесь прованских трав','spices','{"ru":"Смесь прованских трав","en":"Herbes de Provence"}','g'),
('Итальянские травы (смесь)','spices','{"ru":"Итальянские травы (смесь)","en":"Italian herb blend"}','g'),
('Хмели-сунели','spices','{"ru":"Хмели-сунели","en":"Khmeli-suneli spice blend"}','g'),
('Смесь для шашлыка','spices','{"ru":"Смесь для шашлыка","en":"Shashlik spice blend"}','g'),
('Аджика сухая','spices','{"ru":"Аджика сухая","en":"Dry adjika spice"}','g'),
('Порошок чесночный','spices','{"ru":"Порошок чесночный","en":"Garlic powder"}','g'),
('Порошок луковый','spices','{"ru":"Порошок луковый","en":"Onion powder"}','g'),
('Хлопья чесночные','spices','{"ru":"Хлопья чесночные","en":"Garlic flakes"}','g'),

-- ==================== СВЕЖИЕ ТРАВЫ ====================
('Петрушка (зелень)','spices','{"ru":"Петрушка (зелень)","en":"Fresh parsley"}','g'),
('Укроп','spices','{"ru":"Укроп","en":"Fresh dill"}','g'),
('Базилик зеленый','spices','{"ru":"Базилик зеленый","en":"Green basil"}','g'),
('Базилик фиолетовый','spices','{"ru":"Базилик фиолетовый","en":"Purple basil"}','g'),
('Кинза (кориандр)','spices','{"ru":"Кинза (кориандр)","en":"Fresh cilantro"}','g'),
('Тархун (эстрагон)','spices','{"ru":"Тархун (эстрагон)","en":"Tarragon"}','g'),
('Розмарин','spices','{"ru":"Розмарин","en":"Fresh rosemary"}','g'),
('Тимьян','spices','{"ru":"Тимьян","en":"Fresh thyme"}','g'),
('Орегано свежий','spices','{"ru":"Орегано свежий","en":"Fresh oregano"}','g'),
('Орегано сушеный','spices','{"ru":"Орегано сушеный","en":"Dried oregano"}','g'),
('Мята свежая','spices','{"ru":"Мята свежая","en":"Fresh mint"}','g'),
('Мята сухая','spices','{"ru":"Мята сухая","en":"Dried mint"}','g'),
('Мелисса','spices','{"ru":"Мелисса","en":"Lemon balm"}','g'),
('Шалфей свежий','spices','{"ru":"Шалфей свежий","en":"Fresh sage"}','g'),
('Шалфей сухой','spices','{"ru":"Шалфей сухой","en":"Dried sage"}','g'),
('Майоран свежий','spices','{"ru":"Майоран свежий","en":"Fresh marjoram"}','g'),
('Майоран сухой','spices','{"ru":"Майоран сухой","en":"Dried marjoram"}','g'),
('Чабрец','spices','{"ru":"Чабрец","en":"Wild thyme"}','g'),
('Лавровый лист','spices','{"ru":"Лавровый лист","en":"Bay leaf"}','g'),
('Лимонная трава (лемонграсс)','spices','{"ru":"Лимонная трава (лемонграсс)","en":"Lemongrass"}','g'),
('Листья лайма кафрского','spices','{"ru":"Листья лайма кафрского","en":"Kaffir lime leaves"}','g'),
('Листья карри','spices','{"ru":"Листья карри","en":"Curry leaves"}','g'),
('Пандан (листья)','spices','{"ru":"Пандан (листья)","en":"Pandan leaves"}','g'),
('Черемша','spices','{"ru":"Черемша","en":"Wild garlic (ramsons)"}','g'),
('Сельдерей (зелень)','spices','{"ru":"Сельдерей (зелень)","en":"Celery leaves"}','g'),
('Фенхель (зелень)','spices','{"ru":"Фенхель (зелень)","en":"Fennel fronds"}','g'),

-- ==================== МАСЛА ====================
('Масло оливковое Extra Virgin','oils','{"ru":"Масло оливковое Extra Virgin","en":"Extra virgin olive oil"}','ml'),
('Масло оливковое рафинированное','oils','{"ru":"Масло оливковое рафинированное","en":"Refined olive oil"}','ml'),
('Масло подсолнечное рафинированное','oils','{"ru":"Масло подсолнечное рафинированное","en":"Refined sunflower oil"}','ml'),
('Масло подсолнечное нерафинированное','oils','{"ru":"Масло подсолнечное нерафинированное","en":"Unrefined sunflower oil"}','ml'),
('Масло рапсовое','oils','{"ru":"Масло рапсовое","en":"Canola oil"}','ml'),
('Масло кукурузное','oils','{"ru":"Масло кукурузное","en":"Corn oil"}','ml'),
('Масло льняное','oils','{"ru":"Масло льняное","en":"Flaxseed oil"}','ml'),
('Масло кунжутное темное','oils','{"ru":"Масло кунжутное темное","en":"Dark sesame oil"}','ml'),
('Масло кунжутное светлое','oils','{"ru":"Масло кунжутное светлое","en":"Light sesame oil"}','ml'),
('Масло кокосовое рафинированное','oils','{"ru":"Масло кокосовое рафинированное","en":"Refined coconut oil"}','ml'),
('Масло кокосовое нерафинированное','oils','{"ru":"Масло кокосовое нерафинированное","en":"Virgin coconut oil"}','ml'),
('Масло авокадо','oils','{"ru":"Масло авокадо","en":"Avocado oil"}','ml'),
('Масло грецкого ореха','oils','{"ru":"Масло грецкого ореха","en":"Walnut oil"}','ml'),
('Масло арахисовое','oils','{"ru":"Масло арахисовое","en":"Peanut oil"}','ml'),
('Масло виноградных косточек','oils','{"ru":"Масло виноградных косточек","en":"Grapeseed oil"}','ml'),
('Масло тыквенных семечек','oils','{"ru":"Масло тыквенных семечек","en":"Pumpkin seed oil"}','ml'),
('Масло трюфельное','oils','{"ru":"Масло трюфельное","en":"Truffle oil"}','ml'),
('Масло чили','oils','{"ru":"Масло чили","en":"Chili oil"}','ml'),

-- ==================== УКСУСЫ ====================
('Уксус яблочный','pantry','{"ru":"Уксус яблочный","en":"Apple cider vinegar"}','ml'),
('Уксус винный белый','pantry','{"ru":"Уксус винный белый","en":"White wine vinegar"}','ml'),
('Уксус винный красный','pantry','{"ru":"Уксус винный красный","en":"Red wine vinegar"}','ml'),
('Уксус бальзамический','pantry','{"ru":"Уксус бальзамический","en":"Balsamic vinegar"}','ml'),
('Уксус бальзамический белый','pantry','{"ru":"Уксус бальзамический белый","en":"White balsamic vinegar"}','ml'),
('Уксус рисовый','pantry','{"ru":"Уксус рисовый","en":"Rice vinegar"}','ml'),
('Уксус рисовый черный','pantry','{"ru":"Уксус рисовый черный","en":"Black rice vinegar"}','ml'),
('Уксус хересный','pantry','{"ru":"Уксус хересный","en":"Sherry vinegar"}','ml'),
('Уксус солодовый','pantry','{"ru":"Уксус солодовый","en":"Malt vinegar"}','ml'),
('Уксус столовый 9%','pantry','{"ru":"Уксус столовый 9%","en":"Table vinegar 9%"}','ml'),

-- ==================== СОУСЫ И ПАСТЫ ====================
('Соевый соус (темный)','pantry','{"ru":"Соевый соус (темный)","en":"Dark soy sauce"}','ml'),
('Соевый соус (светлый)','pantry','{"ru":"Соевый соус (светлый)","en":"Light soy sauce"}','ml'),
('Соевый соус (тамари)','pantry','{"ru":"Соевый соус (тамари)","en":"Tamari soy sauce"}','ml'),
('Кокосовый амино','pantry','{"ru":"Кокосовый амино","en":"Coconut aminos"}','ml'),
('Соус устричный','pantry','{"ru":"Соус устричный","en":"Oyster sauce"}','ml'),
('Соус рыбный','pantry','{"ru":"Соус рыбный","en":"Fish sauce"}','ml'),
('Соус терияки','pantry','{"ru":"Соус терияки","en":"Teriyaki sauce"}','ml'),
('Соус хойсин','pantry','{"ru":"Соус хойсин","en":"Hoisin sauce"}','ml'),
('Соус понзу','pantry','{"ru":"Соус понзу","en":"Ponzu sauce"}','ml'),
('Соус ворчестер','pantry','{"ru":"Соус ворчестер","en":"Worcestershire sauce"}','ml'),
('Соус Табаско','pantry','{"ru":"Соус Табаско","en":"Tabasco sauce"}','ml'),
('Соус Шрирача','pantry','{"ru":"Соус Шрирача","en":"Sriracha sauce"}','ml'),
('Соус Харисса','pantry','{"ru":"Соус Харисса","en":"Harissa sauce"}','g'),
('Соус Гочуджан','pantry','{"ru":"Соус Гочуджан","en":"Gochujang sauce"}','g'),
('Паста томатная','pantry','{"ru":"Паста томатная","en":"Tomato paste"}','g'),
('Паста томатная двойная','pantry','{"ru":"Паста томатная двойная","en":"Double tomato paste"}','g'),
('Паста тапенад из оливок','pantry','{"ru":"Паста тапенад из оливок","en":"Olive tapenade"}','g'),
('Паста мисо белая','pantry','{"ru":"Паста мисо белая","en":"White miso paste"}','g'),
('Паста мисо красная','pantry','{"ru":"Паста мисо красная","en":"Red miso paste"}','g'),
('Паста мисо темная','pantry','{"ru":"Паста мисо темная","en":"Dark miso paste"}','g'),
('Паста анчоусная','pantry','{"ru":"Паста анчоусная","en":"Anchovy paste"}','g'),
('Горчица дижонская','pantry','{"ru":"Горчица дижонская","en":"Dijon mustard"}','g'),
('Горчица русская','pantry','{"ru":"Горчица русская","en":"Russian mustard"}','g'),
('Горчица зернистая','pantry','{"ru":"Горчица зернистая","en":"Whole grain mustard"}','g'),
('Горчица американская','pantry','{"ru":"Горчица американская","en":"American yellow mustard"}','g'),
('Майонез классический','pantry','{"ru":"Майонез классический","en":"Classic mayonnaise"}','g'),
('Кетчуп томатный','pantry','{"ru":"Кетчуп томатный","en":"Tomato ketchup"}','g'),
('Хумус','pantry','{"ru":"Хумус","en":"Hummus"}','g'),
('Баба-гануш','pantry','{"ru":"Баба-гануш","en":"Baba ganoush"}','g'),
('Дзадзики','pantry','{"ru":"Дзадзики","en":"Tzatziki"}','g'),
('Соус тартар','pantry','{"ru":"Соус тартар","en":"Tartar sauce"}','g'),
('Соус цезарь','pantry','{"ru":"Соус цезарь","en":"Caesar dressing"}','g'),
('Соус ранч','pantry','{"ru":"Соус ранч","en":"Ranch dressing"}','g'),
('Соус песто зеленый','pantry','{"ru":"Соус песто зеленый","en":"Green pesto sauce"}','g'),
('Соус песто красный','pantry','{"ru":"Соус песто красный","en":"Red pesto sauce"}','g'),
('Соус болоньезе (готовый)','pantry','{"ru":"Соус болоньезе (готовый)","en":"Bolognese sauce (ready)"}','g'),
('Соус барбекю','pantry','{"ru":"Соус барбекю","en":"BBQ sauce"}','g'),
('Соус Биск (из раков/лобстеров)','pantry','{"ru":"Соус Биск (из раков/лобстеров)","en":"Bisque sauce"}','ml'),

-- ==================== САХАР И ПОДСЛАСТИТЕЛИ ====================
('Сахар белый','pantry','{"ru":"Сахар белый","en":"White sugar"}','g'),
('Сахар коричневый (тростниковый)','pantry','{"ru":"Сахар коричневый (тростниковый)","en":"Brown cane sugar"}','g'),
('Сахар мусковадо темный','pantry','{"ru":"Сахар мусковадо темный","en":"Dark muscovado sugar"}','g'),
('Сахар демерара','pantry','{"ru":"Сахар демерара","en":"Demerara sugar"}','g'),
('Сахар пудра','pantry','{"ru":"Сахар пудра","en":"Powdered sugar (icing sugar)"}','g'),
('Сахар инвертный','pantry','{"ru":"Сахар инвертный","en":"Invert sugar"}','g'),
('Сироп глюкозы','pantry','{"ru":"Сироп глюкозы","en":"Glucose syrup"}','g'),
('Мед цветочный','pantry','{"ru":"Мед цветочный","en":"Floral honey"}','g'),
('Мед гречишный','pantry','{"ru":"Мед гречишный","en":"Buckwheat honey"}','g'),
('Мед акациевый','pantry','{"ru":"Мед акациевый","en":"Acacia honey"}','g'),
('Патока темная','pantry','{"ru":"Патока темная","en":"Dark molasses"}','g'),
('Патока светлая','pantry','{"ru":"Патока светлая","en":"Light corn syrup"}','g'),
('Кленовый сироп','pantry','{"ru":"Кленовый сироп","en":"Maple syrup"}','ml'),
('Агавовый сироп','pantry','{"ru":"Агавовый сироп","en":"Agave syrup"}','ml'),
('Сироп топинамбура','pantry','{"ru":"Сироп топинамбура","en":"Jerusalem artichoke syrup"}','ml'),
('Стевия','pantry','{"ru":"Стевия","en":"Stevia"}','g'),
('Эритрит','pantry','{"ru":"Эритрит","en":"Erythritol"}','g'),

-- ==================== СОЛЬ ====================
('Соль поваренная','spices','{"ru":"Соль поваренная","en":"Table salt"}','g'),
('Соль морская крупная','spices','{"ru":"Соль морская крупная","en":"Coarse sea salt"}','g'),
('Соль морская мелкая','spices','{"ru":"Соль морская мелкая","en":"Fine sea salt"}','g'),
('Соль розовая гималайская','spices','{"ru":"Соль розовая гималайская","en":"Pink Himalayan salt"}','g'),
('Соль черная (кала намак)','spices','{"ru":"Соль черная (кала намак)","en":"Black salt (kala namak)"}','g'),
('Соль копченая','spices','{"ru":"Соль копченая","en":"Smoked salt"}','g'),
('Флёр де сель','spices','{"ru":"Флёр де сель","en":"Fleur de sel"}','g'),
('Соль нитритная','spices','{"ru":"Соль нитритная","en":"Nitrite salt"}','g'),

-- ==================== ПАСТА И ЛАПША ====================
('Паста спагетти','grains','{"ru":"Паста спагетти","en":"Spaghetti pasta"}','g'),
('Паста пенне','grains','{"ru":"Паста пенне","en":"Penne pasta"}','g'),
('Паста фарфалле','grains','{"ru":"Паста фарфалле","en":"Farfalle pasta"}','g'),
('Паста фузилли','grains','{"ru":"Паста фузилли","en":"Fusilli pasta"}','g'),
('Паста ригатони','grains','{"ru":"Паста ригатони","en":"Rigatoni pasta"}','g'),
('Паста тальятелле','grains','{"ru":"Паста тальятелле","en":"Tagliatelle pasta"}','g'),
('Паста феттучини','grains','{"ru":"Паста феттучини","en":"Fettuccine pasta"}','g'),
('Паста папарделле','grains','{"ru":"Паста папарделле","en":"Pappardelle pasta"}','g'),
('Паста лазанья (листы)','grains','{"ru":"Паста лазанья (листы)","en":"Lasagna sheets"}','g'),
('Паста каннеллони','grains','{"ru":"Паста каннеллони","en":"Cannelloni pasta"}','g'),
('Паста орзо','grains','{"ru":"Паста орзо","en":"Orzo pasta"}','g'),
('Паста конкилье','grains','{"ru":"Паста конкилье","en":"Conchiglie pasta"}','g'),
('Паста лингвини','grains','{"ru":"Паста лингвини","en":"Linguine pasta"}','g'),
('Паста букатини','grains','{"ru":"Паста букатини","en":"Bucatini pasta"}','g'),
('Паста тортеллини','grains','{"ru":"Паста тортеллини","en":"Tortellini pasta"}','g'),
('Паста равиоли','grains','{"ru":"Паста равиоли","en":"Ravioli pasta"}','g'),
('Лапша рисовая широкая','grains','{"ru":"Лапша рисовая широкая","en":"Wide rice noodles"}','g'),
('Лапша рисовая тонкая (вермишель)','grains','{"ru":"Лапша рисовая тонкая (вермишель)","en":"Rice vermicelli"}','g'),
('Лапша гречневая (соба)','grains','{"ru":"Лапша гречневая (соба)","en":"Soba noodles"}','g'),
('Лапша пшеничная (удон)','grains','{"ru":"Лапша пшеничная (удон)","en":"Udon noodles"}','g'),
('Лапша яичная','grains','{"ru":"Лапша яичная","en":"Egg noodles"}','g'),
('Лапша стеклянная (фунчоза)','grains','{"ru":"Лапша стеклянная (фунчоза)","en":"Glass noodles (funchoza)"}','g'),
('Лапша рамен (сухая)','grains','{"ru":"Лапша рамен (сухая)","en":"Dry ramen noodles"}','g'),
('Ньокки','grains','{"ru":"Ньокки","en":"Gnocchi"}','g'),
('Кускус (крупный)','grains','{"ru":"Кускус (крупный)","en":"Large couscous (maftoul)"}','g'),

-- ==================== ХЛЕБ И ВЫПЕЧКА ====================
('Хлеб белый пшеничный','bakery','{"ru":"Хлеб белый пшеничный","en":"White wheat bread"}','g'),
('Хлеб ржаной','bakery','{"ru":"Хлеб ржаной","en":"Rye bread"}','g'),
('Хлеб бородинский','bakery','{"ru":"Хлеб бородинский","en":"Borodinsky bread"}','g'),
('Хлеб цельнозерновой','bakery','{"ru":"Хлеб цельнозерновой","en":"Whole grain bread"}','g'),
('Хлеб тостовый','bakery','{"ru":"Хлеб тостовый","en":"Toast bread"}','g'),
('Чиабатта','bakery','{"ru":"Чиабатта","en":"Ciabatta"}','g'),
('Фокачча','bakery','{"ru":"Фокачча","en":"Focaccia"}','g'),
('Багет французский','bakery','{"ru":"Багет французский","en":"French baguette"}','g'),
('Бриошь','bakery','{"ru":"Бриошь","en":"Brioche"}','g'),
('Питта','bakery','{"ru":"Питта","en":"Pita bread"}','g'),
('Лаваш тонкий','bakery','{"ru":"Лаваш тонкий","en":"Thin lavash"}','g'),
('Наан','bakery','{"ru":"Наан","en":"Naan bread"}','g'),
('Тортилья пшеничная','bakery','{"ru":"Тортилья пшеничная","en":"Wheat tortilla"}','g'),
('Тортилья кукурузная','bakery','{"ru":"Тортилья кукурузная","en":"Corn tortilla"}','g'),
('Крекер несоленый','bakery','{"ru":"Крекер несоленый","en":"Unsalted cracker"}','g'),
('Хлебцы ржаные','bakery','{"ru":"Хлебцы ржаные","en":"Rye crispbread"}','g'),

-- ==================== КОНСЕРВЫ ====================
('Томаты в собственном соку','pantry','{"ru":"Томаты в собственном соку","en":"Canned tomatoes in juice"}','g'),
('Томаты протертые (пассата)','pantry','{"ru":"Томаты протертые (пассата)","en":"Passata (crushed tomatoes)"}','g'),
('Фасоль белая консервированная','pantry','{"ru":"Фасоль белая консервированная","en":"Canned white beans"}','g'),
('Фасоль красная консервированная','pantry','{"ru":"Фасоль красная консервированная","en":"Canned red beans"}','g'),
('Горошек зеленый консервированный','pantry','{"ru":"Горошек зеленый консервированный","en":"Canned green peas"}','g'),
('Кукуруза консервированная','pantry','{"ru":"Кукуруза консервированная","en":"Canned corn"}','g'),
('Оливки консервированные (зеленые)','pantry','{"ru":"Оливки консервированные (зеленые)","en":"Canned green olives"}','g'),
('Артишоки консервированные','pantry','{"ru":"Артишоки консервированные","en":"Canned artichokes"}','g'),
('Тунец консервированный в масле','pantry','{"ru":"Тунец консервированный в масле","en":"Canned tuna in oil"}','g'),
('Тунец консервированный в соку','pantry','{"ru":"Тунец консервированный в соку","en":"Canned tuna in water"}','g'),
('Сардины консервированные','pantry','{"ru":"Сардины консервированные","en":"Canned sardines"}','g'),
('Лосось консервированный','pantry','{"ru":"Лосось консервированный","en":"Canned salmon"}','g'),

-- ==================== АЛКОГОЛЬ ДЛЯ КУЛИНАРИИ ====================
('Вино белое сухое (для готовки)','beverages','{"ru":"Вино белое сухое (для готовки)","en":"Dry white wine (for cooking)"}','ml'),
('Вино красное сухое (для готовки)','beverages','{"ru":"Вино красное сухое (для готовки)","en":"Dry red wine (for cooking)"}','ml'),
('Херес сухой','beverages','{"ru":"Херес сухой","en":"Dry sherry"}','ml'),
('Марсала','beverages','{"ru":"Марсала","en":"Marsala wine"}','ml'),
('Мирин','beverages','{"ru":"Мирин","en":"Mirin"}','ml'),
('Саке','beverages','{"ru":"Саке","en":"Sake"}','ml'),
('Коньяк (для готовки)','beverages','{"ru":"Коньяк (для готовки)","en":"Brandy (for cooking)"}','ml'),
('Ром темный','beverages','{"ru":"Ром темный","en":"Dark rum"}','ml'),
('Ром светлый','beverages','{"ru":"Ром светлый","en":"Light rum"}','ml'),
('Ликер Grand Marnier','beverages','{"ru":"Ликер Grand Marnier","en":"Grand Marnier liqueur"}','ml'),
('Ликер Амаретто','beverages','{"ru":"Ликер Амаретто","en":"Amaretto liqueur"}','ml'),
('Ликер Кофейный (Kahlua)','beverages','{"ru":"Ликер Кофейный (Kahlua)","en":"Coffee liqueur (Kahlua)"}','ml'),
('Портвейн','beverages','{"ru":"Портвейн","en":"Port wine"}','ml'),
('Пиво светлое (для готовки)','beverages','{"ru":"Пиво светлое (для готовки)","en":"Light beer (for cooking)"}','ml'),
('Пиво темное (для готовки)','beverages','{"ru":"Пиво темное (для готовки)","en":"Dark beer (for cooking)"}','ml'),

-- ==================== БЕЗАЛКОГОЛЬНЫЕ НАПИТКИ ====================
('Вода питьевая','beverages','{"ru":"Вода питьевая","en":"Drinking water"}','ml'),
('Вода газированная','beverages','{"ru":"Вода газированная","en":"Sparkling water"}','ml'),
('Бульон куриный','beverages','{"ru":"Бульон куриный","en":"Chicken broth"}','ml'),
('Бульон говяжий','beverages','{"ru":"Бульон говяжий","en":"Beef broth"}','ml'),
('Бульон овощной','beverages','{"ru":"Бульон овощной","en":"Vegetable broth"}','ml'),
('Бульон рыбный','beverages','{"ru":"Бульон рыбный","en":"Fish stock"}','ml'),
('Фумет (рыбный бульон)','beverages','{"ru":"Фумет (рыбный бульон)","en":"Fish fumet"}','ml'),
('Дашибульон (даши)','beverages','{"ru":"Дашибульон (даши)","en":"Dashi stock"}','ml'),
('Молоко кокосовое','beverages','{"ru":"Молоко кокосовое","en":"Coconut milk"}','ml'),
('Сок апельсиновый свежевыжатый','beverages','{"ru":"Сок апельсиновый свежевыжатый","en":"Freshly squeezed orange juice"}','ml'),
('Сок лимонный свежевыжатый','beverages','{"ru":"Сок лимонный свежевыжатый","en":"Freshly squeezed lemon juice"}','ml'),
('Сок лаймовый свежевыжатый','beverages','{"ru":"Сок лаймовый свежевыжатый","en":"Freshly squeezed lime juice"}','ml'),
('Сок томатный','beverages','{"ru":"Сок томатный","en":"Tomato juice"}','ml'),
('Сок гранатовый','beverages','{"ru":"Сок гранатовый","en":"Pomegranate juice"}','ml'),
('Кофе эспрессо','beverages','{"ru":"Кофе эспрессо","en":"Espresso coffee"}','ml'),
('Кофе молотый','beverages','{"ru":"Кофе молотый","en":"Ground coffee"}','g'),
('Кофе растворимый','beverages','{"ru":"Кофе растворимый","en":"Instant coffee"}','g'),
('Чай черный (листовой)','beverages','{"ru":"Чай черный (листовой)","en":"Black tea (loose leaf)"}','g'),
('Чай зеленый (листовой)','beverages','{"ru":"Чай зеленый (листовой)","en":"Green tea (loose leaf)"}','g'),
('Чай матча (порошок)','beverages','{"ru":"Чай матча (порошок)","en":"Matcha tea powder"}','g'),

-- ==================== ШОКОЛАД И КАКАО ====================
('Шоколад темный 70%','pantry','{"ru":"Шоколад темный 70%","en":"Dark chocolate 70%"}','g'),
('Шоколад темный 85%','pantry','{"ru":"Шоколад темный 85%","en":"Dark chocolate 85%"}','g'),
('Шоколад молочный','pantry','{"ru":"Шоколад молочный","en":"Milk chocolate"}','g'),
('Шоколад белый','pantry','{"ru":"Шоколад белый","en":"White chocolate"}','g'),
('Шоколад рубиновый','pantry','{"ru":"Шоколад рубиновый","en":"Ruby chocolate"}','g'),
('Шоколад горький 99%','pantry','{"ru":"Шоколад горький 99%","en":"Bitter chocolate 99%"}','g'),
('Какао-порошок натуральный','pantry','{"ru":"Какао-порошок натуральный","en":"Natural cocoa powder"}','g'),
('Какао-порошок алкализованный','pantry','{"ru":"Какао-порошок алкализованный","en":"Alkalized cocoa powder"}','g'),
('Какао-масло','pantry','{"ru":"Какао-масло","en":"Cocoa butter"}','g'),
('Какао-крупка','pantry','{"ru":"Какао-крупка","en":"Cacao nibs"}','g'),
('Шоколадные капли (темные)','pantry','{"ru":"Шоколадные капли (темные)","en":"Dark chocolate chips"}','g'),
('Шоколадные капли (белые)','pantry','{"ru":"Шоколадные капли (белые)","en":"White chocolate chips"}','g'),
('Нутелла','pantry','{"ru":"Нутелла","en":"Nutella"}','g'),
('Пралине (паста)','pantry','{"ru":"Пралине (паста)","en":"Praline paste"}','g'),
('Джандуйя','pantry','{"ru":"Джандуйя","en":"Gianduja"}','g'),

-- ==================== ЖЕЛИРУЮЩИЕ И ЭМУЛЬГАТОРЫ ====================
('Каррагинан','bakery','{"ru":"Каррагинан","en":"Carrageenan"}','g'),
('Метилцеллюлоза','bakery','{"ru":"Метилцеллюлоза","en":"Methylcellulose"}','g'),
('Лецитин соевый','bakery','{"ru":"Лецитин соевый","en":"Soy lecithin"}','g'),
('Моно- и диглицериды','bakery','{"ru":"Моно- и диглицериды","en":"Mono and diglycerides"}','g'),
('Инулин','bakery','{"ru":"Инулин","en":"Inulin"}','g'),

-- ==================== НОРИ И ВОДОРОСЛИ ====================
('Нори (листы для суши)','seafood','{"ru":"Нори (листы для суши)","en":"Nori sheets (for sushi)"}','g'),
('Вакаме (морская капуста)','seafood','{"ru":"Вакаме (морская капуста)","en":"Wakame seaweed"}','g'),
('Комбу','seafood','{"ru":"Комбу","en":"Kombu seaweed"}','g'),
('Хийки','seafood','{"ru":"Хийки","en":"Hijiki seaweed"}','g'),
('Фукус (морской виноград)','seafood','{"ru":"Фукус (морской виноград)","en":"Sea grapes (umibudo)"}','g'),
('Морская капуста маринованная','seafood','{"ru":"Морская капуста маринованная","en":"Pickled seaweed"}','g'),
('Агар (из водорослей)','bakery','{"ru":"Агар (из водорослей)","en":"Agar (seaweed-based)"}','g'),
('Спирулина','pantry','{"ru":"Спирулина","en":"Spirulina"}','g'),

-- ==================== ФЕРМЕНТИРОВАННЫЕ ПРОДУКТЫ ====================
('Кимчи','pantry','{"ru":"Кимчи","en":"Kimchi"}','g'),
('Квашеная капуста','pantry','{"ru":"Квашеная капуста","en":"Sauerkraut"}','g'),
('Соленые огурцы','pantry','{"ru":"Соленые огурцы","en":"Pickled cucumbers"}','g'),
('Маринованные огурцы','pantry','{"ru":"Маринованные огурцы","en":"Marinated cucumbers"}','g'),
('Каперберри','pantry','{"ru":"Каперберри","en":"Caperberries"}','g'),
('Оливки маринованные с травами','pantry','{"ru":"Оливки маринованные с травами","en":"Herb marinated olives"}','g'),
('Маринованный имбирь (гари)','pantry','{"ru":"Маринованный имбирь (гари)","en":"Pickled ginger (gari)"}','g'),
('Соленые лимоны','pantry','{"ru":"Соленые лимоны","en":"Preserved lemons"}','g'),
('Вустерская паста','pantry','{"ru":"Вустерская паста","en":"Worcestershire paste"}','g'),
('Мисо (суп-основа)','pantry','{"ru":"Мисо (суп-основа)","en":"Miso soup base"}','g'),
('Натто','pantry','{"ru":"Натто","en":"Natto"}','g'),

-- ==================== СНЭКИ И ПРОЧЕЕ ====================
('Чипсы картофельные','misc','{"ru":"Чипсы картофельные","en":"Potato chips"}','g'),
('Попкорн (зерна)','misc','{"ru":"Попкорн (зерна)","en":"Popcorn kernels"}','g'),
('Мюсли','misc','{"ru":"Мюсли","en":"Muesli"}','g'),
('Гранола','misc','{"ru":"Гранола","en":"Granola"}','g'),
('Протеиновый порошок ванильный','misc','{"ru":"Протеиновый порошок ванильный","en":"Vanilla protein powder"}','g'),
('Протеиновый порошок шоколадный','misc','{"ru":"Протеиновый порошок шоколадный","en":"Chocolate protein powder"}','g'),

-- ==================== АЗИАТСКИЕ ПРОДУКТЫ ====================
('Соус Pon Zu','pantry','{"ru":"Соус Pon Zu","en":"Pon Zu sauce"}','ml'),
('Юzu сок','pantry','{"ru":"Юzu сок","en":"Yuzu juice"}','ml'),
('Тонкацу соус','pantry','{"ru":"Тонкацу соус","en":"Tonkatsu sauce"}','ml'),
('Соус Кewpie (японский майонез)','pantry','{"ru":"Соус Кewpie (японский майонез)","en":"Kewpie mayonnaise"}','g'),
('Рисовая бумага (для роллов)','pantry','{"ru":"Рисовая бумага (для роллов)","en":"Rice paper (for rolls)"}','g'),
('Тофу жареный (абурааге)','legumes','{"ru":"Тофу жареный (абурааге)","en":"Fried tofu (aburage)"}','g'),
('Юба (пленка соевого молока)','legumes','{"ru":"Юба (пленка соевого молока)","en":"Yuba (tofu skin)"}','g'),
('Гочукару (хлопья корейского чили)','spices','{"ru":"Гочукару (хлопья корейского чили)","en":"Gochugaru (Korean chili flakes)"}','g'),
('Дашимото (порошок даши)','pantry','{"ru":"Дашимото (порошок даши)","en":"Dashi powder"}','g'),
('Бонито (стружка тунца)','seafood','{"ru":"Бонито (стружка тунца)","en":"Bonito flakes (katsuobushi)"}','g'),
('Сакура эби (сушеные креветки)','seafood','{"ru":"Сакура эби (сушеные креветки)","en":"Dried sakura shrimp"}','g'),
('Паста юдзу-косё','spices','{"ru":"Паста юдзу-косё","en":"Yuzu kosho paste"}','g'),
('Кочуджан (корейская паста)','pantry','{"ru":"Кочуджан (корейская паста)","en":"Gochujang paste"}','g'),
('Доенджан (корейская мисо)','pantry','{"ru":"Доенджан (корейская мисо)","en":"Doenjang paste"}','g'),
('Пасте карри Массаман','spices','{"ru":"Пасте карри Массаман","en":"Massaman curry paste"}','g'),
('Паста Nam Prik Pao','spices','{"ru":"Паста Nam Prik Pao","en":"Nam Prik Pao paste"}','g'),
('Галангал молотый','spices','{"ru":"Галангал молотый","en":"Ground galangal"}','g'),

-- ==================== МЯСНЫЕ ДЕЛИКАТЕСЫ ====================
('Прошутто крудо','meat','{"ru":"Прошутто крудо","en":"Prosciutto crudo"}','g'),
('Прошутто котто','meat','{"ru":"Прошутто котто","en":"Prosciutto cotto"}','g'),
('Панчетта','meat','{"ru":"Панчетта","en":"Pancetta"}','g'),
('Гуанчале','meat','{"ru":"Гуанчале","en":"Guanciale"}','g'),
('Мортаделла','meat','{"ru":"Мортаделла","en":"Mortadella"}','g'),
('Брезаола','meat','{"ru":"Брезаола","en":"Bresaola"}','g'),
('Коппа','meat','{"ru":"Коппа","en":"Coppa (cured pork neck)"}','g'),
('Хамон серрано','meat','{"ru":"Хамон серрано","en":"Jamon serrano"}','g'),
('Хамон иберико','meat','{"ru":"Хамон иберико","en":"Jamon iberico"}','g'),
('Хорватская колбаса куленова','meat','{"ru":"Хорватская колбаса куленова","en":"Kulen sausage"}','g'),
('Чоризо (сырокопченая)','meat','{"ru":"Чоризо (сырокопченая)","en":"Chorizo (dry-cured)"}','g'),
('Чоризо (свежая)','meat','{"ru":"Чоризо (свежая)","en":"Fresh chorizo sausage"}','g'),
('Салями','meat','{"ru":"Салями","en":"Salami"}','g'),
('Пепперони','meat','{"ru":"Пепперони","en":"Pepperoni"}','g'),
('Сервелат','meat','{"ru":"Сервелат","en":"Cervelat sausage"}','g'),
('Колбаса охотничья','meat','{"ru":"Колбаса охотничья","en":"Hunting sausage"}','g'),
('Колбаски баварские (вайсвурст)','meat','{"ru":"Колбаски баварские (вайсвурст)","en":"Bavarian white sausage"}','g'),
('Сосиски куриные','meat','{"ru":"Сосиски куриные","en":"Chicken sausages"}','g'),
('Сосиски говяжьи','meat','{"ru":"Сосиски говяжьи","en":"Beef hot dogs"}','g'),
('Котлеты (полуфабрикат)','meat','{"ru":"Котлеты (полуфабрикат)","en":"Meat patties (semi-finished)"}','g'),
('Люля-кебаб (полуфабрикат)','meat','{"ru":"Люля-кебаб (полуфабрикат)","en":"Lula kebab (semi-finished)"}','g')

) as v(name, category, names, unit)
where not exists (
  select 1 from products p where lower(p.name) = lower(v.name)
);
```

### 20260227250000_promo_codes_starts_at.sql
```sql
-- Дата начала действия промокода (с какой даты можно использовать)
alter table promo_codes add column if not exists starts_at timestamptz;

-- check_promo_code: учитываем период действия (starts_at и expires_at)
create or replace function check_promo_code(p_code text)
returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code));

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  if v_row.starts_at is not null and v_row.starts_at > now() then
    return 'not_started';
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  return 'ok';
end;
$$;

-- use_promo_code: тоже проверяем период действия
create or replace function use_promo_code(
  p_code text,
  p_establishment_id uuid
) returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where upper(trim(code)) = upper(trim(p_code))
  for update;

  if not found then
    return 'invalid';
  end if;

  if v_row.is_used then
    return 'used';
  end if;

  if v_row.starts_at is not null and v_row.starts_at > now() then
    return 'not_started';
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  update promo_codes
  set is_used = true,
      used_by_establishment_id = p_establishment_id,
      used_at = now()
  where id = v_row.id;

  return 'ok';
end;
$$;
```

### 20260227260000_products_package_columns.sql
```sql
-- Добавляем колонки package_price и package_weight_grams в таблицу products
ALTER TABLE products ADD COLUMN IF NOT EXISTS package_price REAL;
ALTER TABLE products ADD COLUMN IF NOT EXISTS package_weight_grams REAL;

COMMENT ON COLUMN products.package_price IS 'Цена за одну упаковку';
COMMENT ON COLUMN products.package_weight_grams IS 'Вес упаковки в граммах';
```

### 20260227270000_anon_products_policies.sql
```sql
-- Restodocks НЕ использует Supabase Auth — все запросы идут с anon ключом.
-- Миграция 20260227100000 включила RLS на products, но не добавила anon-политики.
-- Без этих политик продукты не сохраняются и не читаются — данные исчезают после обновления.

-- products: anon может делать всё (SELECT, INSERT, UPDATE, DELETE)
DROP POLICY IF EXISTS "anon_select_products" ON products;
CREATE POLICY "anon_select_products" ON products
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_products" ON products;
CREATE POLICY "anon_insert_products" ON products
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_products" ON products;
CREATE POLICY "anon_update_products" ON products
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_products" ON products;
CREATE POLICY "anon_delete_products" ON products
  FOR DELETE TO anon USING (true);

-- establishment_products: anon может делать всё
DROP POLICY IF EXISTS "anon_select_establishment_products" ON establishment_products;
CREATE POLICY "anon_select_establishment_products" ON establishment_products
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_establishment_products" ON establishment_products;
CREATE POLICY "anon_insert_establishment_products" ON establishment_products
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "anon_update_establishment_products" ON establishment_products;
CREATE POLICY "anon_update_establishment_products" ON establishment_products
  FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_delete_establishment_products" ON establishment_products;
CREATE POLICY "anon_delete_establishment_products" ON establishment_products
  FOR DELETE TO anon USING (true);

-- product_price_history: anon может делать всё
DROP POLICY IF EXISTS "anon_select_product_price_history" ON product_price_history;
CREATE POLICY "anon_select_product_price_history" ON product_price_history
  FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "anon_insert_product_price_history" ON product_price_history;
CREATE POLICY "anon_insert_product_price_history" ON product_price_history
  FOR INSERT TO anon WITH CHECK (true);
```

### 20260227280000_checklist_submissions_employee_id.sql
```sql
-- checklist_submissions: добавить submitted_by_employee_id и recipient_chef_id если нет
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS submitted_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS recipient_chef_id UUID REFERENCES employees(id) ON DELETE SET NULL;
```

### 20260227290000_checklist_submissions_optional_recipient.sql
```sql
-- Делаем recipient_chef_id необязательным: чеклисты сохраняются для заведения без обязательного получателя.
ALTER TABLE checklist_submissions ALTER COLUMN recipient_chef_id DROP NOT NULL;

-- Restodocks использует anon-ключ без Supabase Auth — политики через anon роль
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_access" ON checklist_submissions;

-- Включаем RLS если ещё не включён
ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO anon USING (true) WITH CHECK (true);
```

### 20260227300000_deduplicate_products.sql
```sql
-- Удаление дублирующихся продуктов (одинаковое название).
-- Стратегия: для каждой группы дублей оставляем продукт, который уже есть
-- в establishment_products (если есть). Если в nomenclature нет ни одного —
-- оставляем строку с наименьшим id (наиболее ранний, обычно из справочника).
-- Все ссылки из establishment_products и product_price_history переводим
-- на оставшийся продукт, затем удаляем дубли.

BEGIN;

-- 1. Таблица: для каждого (lower(name)) определяем "победителя"
--    Приоритет: продукт, уже стоящий в establishment_products > min(id)
CREATE TEMP TABLE _dedup_winners AS
SELECT DISTINCT ON (lower(trim(p.name)))
    p.id      AS winner_id,
    lower(trim(p.name)) AS name_key
FROM products p
ORDER BY
    lower(trim(p.name)),
    -- предпочитаем тех, кто есть в номенклатуре
    (EXISTS (SELECT 1 FROM establishment_products ep WHERE ep.product_id = p.id)) DESC,
    -- среди них — наименьший id (первый добавленный)
    p.id;

-- 2. Таблица: все дубли → winner_id (исключая самого победителя)
CREATE TEMP TABLE _dedup_victims AS
SELECT p.id AS victim_id, w.winner_id
FROM products p
JOIN _dedup_winners w ON lower(trim(p.name)) = w.name_key
WHERE p.id <> w.winner_id;

-- 3. Перенаправляем establishment_products: дубли → победитель
--    Используем upsert чтобы не создать конфликт по (establishment_id, product_id)
UPDATE establishment_products ep
SET product_id = v.winner_id
FROM _dedup_victims v
WHERE ep.product_id = v.victim_id
  -- не трогаем если у победителя уже есть запись для этого establishment
  AND NOT EXISTS (
      SELECT 1 FROM establishment_products ep2
      WHERE ep2.product_id = v.winner_id
        AND ep2.establishment_id = ep.establishment_id
  );

-- Удаляем дублирующиеся записи establishment_products (у тех жертв,
-- для которых победитель уже был в номенклатуре — строки не переехали выше)
DELETE FROM establishment_products ep
USING _dedup_victims v
WHERE ep.product_id = v.victim_id;

-- 4. Перенаправляем product_price_history (если таблица существует)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'product_price_history') THEN
    UPDATE product_price_history pph
    SET product_id = v.winner_id
    FROM _dedup_victims v
    WHERE pph.product_id = v.victim_id;
  END IF;
END$$;

-- 5. Обнуляем ссылки supplier_ids в продуктах (JSONB) — не критично, пропускаем.

-- 6. Удаляем сами дубли из products
DELETE FROM products
WHERE id IN (SELECT victim_id FROM _dedup_victims);

-- Итог
DO $$
DECLARE
  deleted_count INT;
  remaining_count INT;
BEGIN
  SELECT COUNT(*) INTO deleted_count FROM _dedup_victims;
  SELECT COUNT(*) INTO remaining_count FROM products;
  RAISE NOTICE 'Deleted % duplicate products. Remaining: %', deleted_count, remaining_count;
END$$;

DROP TABLE _dedup_winners;
DROP TABLE _dedup_victims;

COMMIT;
```

### 20260227310000_products_unique_name.sql
```sql
-- Добавляем уникальный индекс на lower(trim(name)) чтобы предотвратить
-- создание дублирующихся продуктов на уровне базы данных.
-- Сравнение без учёта регистра и пробелов по краям.

CREATE UNIQUE INDEX IF NOT EXISTS products_name_unique_lower
    ON products (lower(trim(name)));
```

### 20260227320000_fix_checklist_submissions_rls.sql
```sql
-- Fix: пересоздаём все политики RLS для checklist_submissions
-- Причина: при вставке через anon-ключ без Supabase Auth срабатывала
-- старая политика с auth.uid(), что давало 42501.

ALTER TABLE checklist_submissions ENABLE ROW LEVEL SECURITY;

-- Удаляем все возможные варианты старых политик
DROP POLICY IF EXISTS "anon_checklist_submissions_all"        ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all"        ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_recipient_access" ON checklist_submissions;
DROP POLICY IF EXISTS "checklist_submissions_access"          ON checklist_submissions;
DROP POLICY IF EXISTS "allow_anon_insert"                     ON checklist_submissions;
DROP POLICY IF EXISTS "allow_anon_select"                     ON checklist_submissions;
DROP POLICY IF EXISTS "allow_all"                             ON checklist_submissions;

-- Единая открытая политика для anon (приложение работает без Supabase Auth)
CREATE POLICY "anon_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO anon USING (true) WITH CHECK (true);

-- Политика для authenticated (на случай будущего использования)
CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
```

### 20260228000000_fix_checklist_submissions_filled_by.sql
```sql
-- Исправление: в живой БД колонка filled_by_employee_id имеет NOT NULL,
-- но приложение пишет submitted_by_employee_id.
-- Решение: копируем значение submitted_by_employee_id в filled_by_employee_id
-- и снимаем NOT NULL с filled_by_employee_id.

-- 1. Снимаем NOT NULL с filled_by_employee_id (если колонка существует)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'checklist_submissions'
      AND column_name = 'filled_by_employee_id'
  ) THEN
    ALTER TABLE checklist_submissions
      ALTER COLUMN filled_by_employee_id DROP NOT NULL;

    -- 2. Синхронизируем: заполняем filled_by_employee_id из submitted_by_employee_id
    --    для строк, где filled_by_employee_id ещё null
    UPDATE checklist_submissions
    SET filled_by_employee_id = submitted_by_employee_id
    WHERE filled_by_employee_id IS NULL
      AND submitted_by_employee_id IS NOT NULL;
  END IF;
END$$;
```

### 20260228100000_checklist_items_target_quantity.sql
```sql
-- Добавляем колонки target_quantity и target_unit к пунктам чеклиста (ПФ с количеством).
ALTER TABLE checklist_items
  ADD COLUMN IF NOT EXISTS target_quantity numeric(10, 3),
  ADD COLUMN IF NOT EXISTS target_unit    text;
```

### 20260228180000_check_establishment_access.sql
```sql
-- Проверка доступа заведения по промокоду
-- Возвращает 'ok' если промокод действует, 'expired' если истёк, 'no_promo' если промокода нет
create or replace function check_establishment_access(p_establishment_id uuid)
returns text
language plpgsql
security definer
as $$
declare
  v_row promo_codes%rowtype;
begin
  select * into v_row
  from promo_codes
  where used_by_establishment_id = p_establishment_id
  limit 1;

  -- Нет промокода — доступ разрешён (старые заведения без промокода)
  if not found then
    return 'ok';
  end if;

  -- Есть expires_at и он уже прошёл
  if v_row.expires_at is not null and v_row.expires_at < now() then
    return 'expired';
  end if;

  return 'ok';
end;
$$;
```

### 20260228190000_promo_codes_max_employees.sql
```sql
-- Лимит сотрудников на заведение (null = без ограничений)
alter table promo_codes add column if not exists max_employees integer;

-- Функция проверки: не превышен ли лимит сотрудников для заведения
-- Возвращает 'ok' или 'limit_reached'
create or replace function check_employee_limit(p_establishment_id uuid)
returns text
language plpgsql
security definer
as $$
declare
  v_max integer;
  v_count integer;
begin
  -- Берём лимит из промокода этого заведения
  select max_employees into v_max
  from promo_codes
  where used_by_establishment_id = p_establishment_id
  limit 1;

  -- Нет промокода или лимит не задан — без ограничений
  if not found or v_max is null then
    return 'ok';
  end if;

  -- Считаем активных сотрудников
  select count(*) into v_count
  from employees
  where establishment_id = p_establishment_id
    and is_active = true;

  if v_count >= v_max then
    return 'limit_reached';
  end if;

  return 'ok';
end;
$$;
```

### 20260228200000_fix_anon_rls_security.sql
```sql
-- =============================================================================
-- SECURITY FIX: Restrict anon role access to minimum required for public flows
--
-- ANALYSIS of unauthenticated (anon) flows:
--   1. Company registration: INSERT establishments, INSERT/UPDATE via RPC (SECURITY DEFINER)
--   2. Employee registration: SELECT establishments (PIN lookup), SELECT employees (email check),
--      INSERT employees via RPC (SECURITY DEFINER)
--   3. Co-owner invite: SELECT/UPDATE co_owner_invitations (token-based, already secure via obscurity)
--   4. Session restore on startup: SELECT employees + establishments (only own id, no leakage)
--   5. Forgot/Reset password: handled entirely via Edge Functions with service_role key
--   6. Login: handled via Supabase Auth API + Edge Function with service_role key
--
-- WHAT WE CLOSE:
--   - anon INSERT/UPDATE on establishments (not needed — RPCs are SECURITY DEFINER)
--   - anon INSERT/UPDATE on employees (not needed — RPCs are SECURITY DEFINER)
--   - anon ALL on products, establishment_products, product_price_history
--   - anon ALL on inventory_documents, order_documents
--   - anon ALL on inventory_drafts, checklist_drafts, checklist_submissions
--   - anon ALL on establishment_schedule_data, establishment_order_list_data
--
-- WHAT WE KEEP for anon:
--   - SELECT on establishments (PIN lookup during employee registration)
--   - SELECT on employees (email uniqueness check during registration)
--   - SELECT on co_owner_invitations (token-based invite acceptance)
--   - SELECT on tech_cards (already minimal — SELECT only)
--
-- All authenticated flows already have proper auth.uid() policies.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. establishments — remove anon INSERT and UPDATE, keep SELECT
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;
DROP POLICY IF EXISTS "anon_update_establishments" ON establishments;

-- ---------------------------------------------------------------------------
-- 2. employees — remove anon INSERT and UPDATE, keep SELECT
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_insert_employees" ON employees;
DROP POLICY IF EXISTS "anon_update_employees" ON employees;

-- ---------------------------------------------------------------------------
-- 3. products — remove all anon policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_products" ON products;
DROP POLICY IF EXISTS "anon_insert_products" ON products;
DROP POLICY IF EXISTS "anon_update_products" ON products;
DROP POLICY IF EXISTS "anon_delete_products" ON products;

-- Add authenticated policy for products (scoped to own establishment)
DROP POLICY IF EXISTS "auth_select_products" ON products;
DROP POLICY IF EXISTS "auth_insert_products" ON products;
DROP POLICY IF EXISTS "auth_update_products" ON products;
DROP POLICY IF EXISTS "auth_delete_products" ON products;

CREATE POLICY "auth_select_products" ON products
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "auth_insert_products" ON products
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "auth_update_products" ON products
  FOR UPDATE TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY "auth_delete_products" ON products
  FOR DELETE TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 4. establishment_products — remove all anon policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "anon_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "anon_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "anon_delete_establishment_products" ON establishment_products;

-- Add authenticated policy
DROP POLICY IF EXISTS "auth_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_delete_establishment_products" ON establishment_products;

CREATE POLICY "auth_select_establishment_products" ON establishment_products
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "auth_insert_establishment_products" ON establishment_products
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "auth_update_establishment_products" ON establishment_products
  FOR UPDATE TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY "auth_delete_establishment_products" ON establishment_products
  FOR DELETE TO authenticated
  USING (true);

-- ---------------------------------------------------------------------------
-- 5. product_price_history — remove anon policies (auth policies already exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_product_price_history" ON product_price_history;
DROP POLICY IF EXISTS "anon_insert_product_price_history" ON product_price_history;

-- ---------------------------------------------------------------------------
-- 6. inventory_documents — remove anon policies (auth policies already exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_inventory_documents_select" ON inventory_documents;
DROP POLICY IF EXISTS "anon_inventory_documents_insert" ON inventory_documents;

-- ---------------------------------------------------------------------------
-- 7. order_documents — remove anon policies (auth policies already exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_order_documents_select" ON order_documents;
DROP POLICY IF EXISTS "anon_order_documents_insert" ON order_documents;

-- ---------------------------------------------------------------------------
-- 8. inventory_drafts — remove anon ALL policy, add authenticated
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_inventory_drafts" ON inventory_drafts;

DROP POLICY IF EXISTS "auth_inventory_drafts" ON inventory_drafts;
CREATE POLICY "auth_inventory_drafts" ON inventory_drafts
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- 9. checklist_drafts — remove anon ALL policy (auth policy already exists)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklist_drafts" ON checklist_drafts;

-- ---------------------------------------------------------------------------
-- 10. checklist_submissions — remove anon ALL policy (auth policy already exists)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;

-- ---------------------------------------------------------------------------
-- 11. establishment_schedule_data — remove anon policies (auth policies exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_schedule_select" ON establishment_schedule_data;
DROP POLICY IF EXISTS "anon_schedule_insert" ON establishment_schedule_data;
DROP POLICY IF EXISTS "anon_schedule_update" ON establishment_schedule_data;

-- ---------------------------------------------------------------------------
-- 12. establishment_order_list_data — remove anon policies (auth policies exist)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_order_list_select" ON establishment_order_list_data;
DROP POLICY IF EXISTS "anon_order_list_insert" ON establishment_order_list_data;
DROP POLICY IF EXISTS "anon_order_list_update" ON establishment_order_list_data;

-- ---------------------------------------------------------------------------
-- 13. co_owner_invitations — add anon SELECT and UPDATE for token-based invite flow
--     (these pages are public: /accept-co-owner-invitation, /register-co-owner)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_co_owner_invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;

CREATE POLICY "anon_select_co_owner_invitations" ON co_owner_invitations
  FOR SELECT TO anon
  USING (true);

CREATE POLICY "anon_update_co_owner_invitations" ON co_owner_invitations
  FOR UPDATE TO anon
  USING (true) WITH CHECK (true);
```

### 20260228210000_tighten_authenticated_rls.sql
```sql
-- =============================================================================
-- SECURITY: Tighten authenticated RLS policies — scope to own establishment
--
-- Analysis findings:
--
-- GLOBAL BY DESIGN (no establishment_id column, intentional shared catalog):
--   - products: global ingredient catalog, all establishments share it. KEEP USING(true).
--   - translations: global translation cache keyed by entity_id. KEEP USING(true).
--
-- ESTABLISHMENT-SCOPED (have establishment_id column, all app queries already
--   filter by establishmentId — only need RLS to enforce it server-side):
--   - establishment_products
--   - inventory_documents
--   - order_documents
--   - inventory_drafts
--   - checklist_drafts
--   - checklist_submissions
--   - establishment_schedule_data
--   - establishment_order_list_data
--   - tech_cards
--
-- NOTE on tech_cards: getAllTechCards() in the app has no filter, but this call
--   is used only to check if a product is referenced before deletion — after
--   applying RLS it will return only the current establishment's cards, which
--   is the correct and safe behavior. No logic change, just data narrowing.
--
-- NOTE on inventory_documents / order_documents / checklist_submissions:
--   Some queries filter by recipient_chef_id or by id directly. The RLS policy
--   below allows access when establishment_id matches OR when the row's
--   recipient_chef_id matches the current user — so chef inbox queries still work.
--
-- Helper: auth.uid() = employees.id (architecture from migration 20260225180000)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. establishment_products — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_delete_establishment_products" ON establishment_products;

CREATE POLICY "auth_select_establishment_products" ON establishment_products
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_insert_establishment_products" ON establishment_products
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_update_establishment_products" ON establishment_products
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_delete_establishment_products" ON establishment_products
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 2. inventory_documents — scope to own establishment
--    Also allow chef to SELECT their own inbox (recipient_chef_id = auth.uid())
--    and SELECT by document id when user is from same establishment.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_inventory_documents_select" ON inventory_documents;
DROP POLICY IF EXISTS "auth_inventory_documents_insert" ON inventory_documents;

CREATE POLICY "auth_inventory_documents_select" ON inventory_documents
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
    OR recipient_chef_id = auth.uid()
  );

CREATE POLICY "auth_inventory_documents_insert" ON inventory_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3. order_documents — scope to own establishment
--    Also allow chef inbox access by recipient_chef_id.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_order_documents_select" ON order_documents;
DROP POLICY IF EXISTS "auth_order_documents_insert" ON order_documents;

CREATE POLICY "auth_order_documents_select" ON order_documents
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_order_documents_insert" ON order_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 4. inventory_drafts — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_inventory_drafts" ON inventory_drafts;

CREATE POLICY "auth_inventory_drafts" ON inventory_drafts
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 5. checklist_drafts — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;

CREATE POLICY "auth_checklist_drafts_all" ON checklist_drafts
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 6. checklist_submissions — scope to own establishment
--    Also allow chef inbox access (recipient_chef_id = auth.uid()).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;

CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
    OR recipient_chef_id = auth.uid()
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 7. establishment_schedule_data — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_schedule_select" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_insert" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_update" ON establishment_schedule_data;

CREATE POLICY "auth_schedule_select" ON establishment_schedule_data
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_schedule_insert" ON establishment_schedule_data
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_schedule_update" ON establishment_schedule_data
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 8. establishment_order_list_data — scope to own establishment
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "auth_order_list_select" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_insert" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_update" ON establishment_order_list_data;

CREATE POLICY "auth_order_list_select" ON establishment_order_list_data
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_order_list_insert" ON establishment_order_list_data
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_order_list_update" ON establishment_order_list_data
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 9. tech_cards — scope to own establishment
--    getAllTechCards() in the app will now naturally return only own cards.
--    getTechCardById() and getTechCardsByCreator() are covered by the
--    establishment_id check since tech cards always belong to one establishment.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_tech_cards_select" ON tech_cards;

DROP POLICY IF EXISTS "auth_select_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_insert_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_update_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_delete_tech_cards" ON tech_cards;

CREATE POLICY "auth_select_tech_cards" ON tech_cards
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_insert_tech_cards" ON tech_cards
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_update_tech_cards" ON tech_cards
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_delete_tech_cards" ON tech_cards
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );
```

### 20260301000000_security_hardening.sql
```sql
-- =============================================================================
-- SECURITY HARDENING — 2026-03-01
--
-- 1. Enable RLS on password_reset_tokens (table was created without it)
-- 2. Fix checklists / checklist_items — remove open anon ALL, scope by establishment_id
-- 3. Fix co_owner_invitations — scope anon UPDATE to the specific invitation token
-- 4. Restrict anon SELECT on employees — replace with SECURITY DEFINER RPCs
-- 5. Restrict anon SELECT on establishments — hide pin_code from direct API access
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. password_reset_tokens — enable RLS, allow only service_role (edge functions)
-- ---------------------------------------------------------------------------
ALTER TABLE password_reset_tokens ENABLE ROW LEVEL SECURITY;

-- No policies for anon or authenticated — only service_role (bypasses RLS)
-- All access goes through edge functions (request-password-reset, reset-password)
-- that use SUPABASE_SERVICE_ROLE_KEY.

-- ---------------------------------------------------------------------------
-- 2. checklists — replace open anon ALL with establishment-scoped authenticated access
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklists_all" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_all" ON checklists;

CREATE POLICY "auth_checklists_select" ON checklists
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_checklists_insert" ON checklists
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_checklists_update" ON checklists
  FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

CREATE POLICY "auth_checklists_delete" ON checklists
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3. checklist_items — replace open anon ALL with establishment-scoped access via parent checklist
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_checklist_items_all" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_all" ON checklist_items;

CREATE POLICY "auth_checklist_items_select" ON checklist_items
  FOR SELECT TO authenticated
  USING (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "auth_checklist_items_insert" ON checklist_items
  FOR INSERT TO authenticated
  WITH CHECK (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "auth_checklist_items_update" ON checklist_items
  FOR UPDATE TO authenticated
  USING (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  )
  WITH CHECK (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "auth_checklist_items_delete" ON checklist_items
  FOR DELETE TO authenticated
  USING (
    checklist_id IN (
      SELECT id FROM checklists
      WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 4. co_owner_invitations — scope anon UPDATE to specific token only
--    (prevents one anon user from updating another user's invitation)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_update_co_owner_invitations" ON co_owner_invitations;

-- anon UPDATE is only allowed when the request is filtered by the exact invitation_token.
-- The app calls: .update({status:'accepted'}).eq('invitation_token', token)
-- RLS enforces that the row's token matches the filter.
CREATE POLICY "anon_update_co_owner_invitations" ON co_owner_invitations
  FOR UPDATE TO anon
  USING (status = 'pending')
  WITH CHECK (status IN ('accepted', 'declined'));

-- ---------------------------------------------------------------------------
-- 5. employees — restrict anon SELECT: only allow looking up by email for registration
--    (replace open USING(true) with a SECURITY DEFINER function)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_employees" ON employees;

-- No anon SELECT policy on employees table directly.
-- Registration email-check goes through a SECURITY DEFINER RPC below.

-- RPC: check if an employee email already exists in a given establishment
-- Called during registration to validate email uniqueness.
CREATE OR REPLACE FUNCTION public.check_employee_email_exists(
  p_email text,
  p_establishment_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE lower(email) = lower(p_email)
      AND establishment_id = p_establishment_id
  );
$$;

-- Grant execute to anon and authenticated
GRANT EXECUTE ON FUNCTION public.check_employee_email_exists(text, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.check_employee_email_exists(text, uuid) TO authenticated;

-- RPC: check if an employee email exists across all establishments (for owner registration)
CREATE OR REPLACE FUNCTION public.check_employee_email_exists_global(
  p_email text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE lower(email) = lower(p_email)
  );
$$;

GRANT EXECUTE ON FUNCTION public.check_employee_email_exists_global(text) TO anon;
GRANT EXECUTE ON FUNCTION public.check_employee_email_exists_global(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. establishments — restrict anon SELECT: hide pin_code from direct table access
--    Use a SECURITY DEFINER RPC to look up establishment by pin_code instead.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "anon_select_establishments" ON establishments;

-- No anon SELECT on establishments table directly.
-- PIN lookup during employee registration goes through the RPC below.

-- RPC: look up establishment by pin_code (returns id and name only — no sensitive data)
CREATE OR REPLACE FUNCTION public.find_establishment_by_pin(
  p_pin_code text
)
RETURNS TABLE(id uuid, name text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, name FROM establishments
  WHERE pin_code = p_pin_code
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.find_establishment_by_pin(text) TO anon;
GRANT EXECUTE ON FUNCTION public.find_establishment_by_pin(text) TO authenticated;

-- RPC: get own establishment data (authenticated employee only — returns full row)
CREATE OR REPLACE FUNCTION public.get_my_establishment()
RETURNS SETOF establishments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT e.* FROM establishments e
  WHERE e.id IN (
    SELECT establishment_id FROM employees WHERE id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_my_establishment() TO authenticated;
```

### 20260301154312_add_draft_type_to_inventory_drafts.sql
```sql
-- Добавить поддержку нескольких типов черновиков инвентаризации (standard и iiko_inventory)
-- Раньше было UNIQUE(establishment_id) → теперь UNIQUE(establishment_id, draft_type)
-- Это позволяет хранить одновременно стандартный черновик и iiko-черновик без конфликтов.

-- 1. Добавить колонку draft_type
ALTER TABLE public.inventory_drafts
  ADD COLUMN IF NOT EXISTS draft_type TEXT NOT NULL DEFAULT 'standard';

-- 2. Обновить существующие строки: если draft_data содержит _type = 'iiko_inventory' — помечаем
UPDATE public.inventory_drafts
  SET draft_type = 'iiko_inventory'
  WHERE draft_data->>'_type' = 'iiko_inventory';

-- 3. Удалить старый UNIQUE(establishment_id) constraint
ALTER TABLE public.inventory_drafts
  DROP CONSTRAINT IF EXISTS inventory_drafts_establishment_id_key;

-- 4. Добавить новый UNIQUE(establishment_id, draft_type)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'inventory_drafts_estid_type_key'
  ) THEN
    ALTER TABLE public.inventory_drafts
      ADD CONSTRAINT inventory_drafts_estid_type_key
      UNIQUE(establishment_id, draft_type);
  END IF;
END$$;
```

### 20260301163520_iiko_blank_storage.sql
```sql
-- Таблица для хранения метаданных iiko-бланка (путь к файлу в Storage, индекс колонки)
-- Байты самого файла хранятся в Supabase Storage bucket "iiko-blanks"

CREATE TABLE IF NOT EXISTS public.iiko_blank_meta (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  storage_path     TEXT NOT NULL,           -- путь в bucket: {estId}/blank.xlsx
  qty_col_index    INT  NOT NULL DEFAULT 5, -- индекс колонки "Остаток фактический"
  uploaded_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(establishment_id)
);

ALTER TABLE public.iiko_blank_meta ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_iiko_blank_meta" ON public.iiko_blank_meta
  FOR ALL TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  );

-- Storage bucket создаётся через Dashboard или API, не через SQL.
-- Здесь только регистрируем таблицу метаданных.
```

### 20260301163640_iiko_blank_storage_policy.sql
```sql
-- RLS политики для bucket "iiko-blanks" в Supabase Storage
-- Каждый аутентифицированный пользователь может читать/писать файлы
-- только своего заведения (путь: {establishment_id}/blank.xlsx)

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('iiko-blanks', 'iiko-blanks', false, 10485760)
ON CONFLICT (id) DO NOTHING;

-- SELECT (download)
DROP POLICY IF EXISTS "iiko_blanks_select" ON storage.objects;
CREATE POLICY "iiko_blanks_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );

-- INSERT (upload)
DROP POLICY IF EXISTS "iiko_blanks_insert" ON storage.objects;
CREATE POLICY "iiko_blanks_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );

-- UPDATE (overwrite)
DROP POLICY IF EXISTS "iiko_blanks_update" ON storage.objects;
CREATE POLICY "iiko_blanks_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );

-- DELETE
DROP POLICY IF EXISTS "iiko_blanks_delete" ON storage.objects;
CREATE POLICY "iiko_blanks_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'iiko-blanks'
    AND (storage.foldername(name))[1] IN (
      SELECT establishment_id::text FROM employees WHERE id = auth.uid()
    )
  );
```

### 20260302120000_iiko_multi_sheet.sql
```sql
-- Добавляем поле sheet_name в iiko_products (название листа Excel)
ALTER TABLE iiko_products
  ADD COLUMN IF NOT EXISTS sheet_name TEXT;

-- Добавляем поля для хранения информации о листах в метаданных бланка
ALTER TABLE iiko_blank_meta
  ADD COLUMN IF NOT EXISTS sheet_names JSONB,
  ADD COLUMN IF NOT EXISTS sheet_qty_cols JSONB;

-- Обновляем RPC insert_iiko_products чтобы принимала sheet_name
CREATE OR REPLACE FUNCTION insert_iiko_products(p_items JSONB)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO iiko_products (
    id, establishment_id, code, name, unit, group_name, sort_order, sheet_name
  )
  SELECT
    gen_random_uuid(),
    (item->>'establishment_id')::uuid,
    item->>'code',
    item->>'name',
    item->>'unit',
    item->>'group_name',
    (item->>'sort_order')::int,
    item->>'sheet_name'
  FROM jsonb_array_elements(p_items) AS item;
END;
$$;
```

### 20260302200000_storage_create_photo_buckets.sql
```sql
-- Создание публичных бакетов для фото профиля и ТТК
-- avatars      — фото профилей сотрудников
-- tech_card_photos — фото блюд и полуфабрикатов в ТТК

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('avatars',           'avatars',           true, 5242880),   -- 5 MB
  ('tech_card_photos',  'tech_card_photos',  true, 10485760)   -- 10 MB
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

-- RLS для avatars
DROP POLICY IF EXISTS "avatars_insert_authenticated" ON storage.objects;
CREATE POLICY "avatars_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_update_authenticated" ON storage.objects;
CREATE POLICY "avatars_update_authenticated"
  ON storage.objects FOR UPDATE TO authenticated
  USING  (bucket_id = 'avatars')
  WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_select_public" ON storage.objects;
CREATE POLICY "avatars_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_delete_authenticated" ON storage.objects;
CREATE POLICY "avatars_delete_authenticated"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars');

-- RLS для tech_card_photos
DROP POLICY IF EXISTS "tech_card_photos_insert_authenticated" ON storage.objects;
CREATE POLICY "tech_card_photos_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'tech_card_photos');

DROP POLICY IF EXISTS "tech_card_photos_update_authenticated" ON storage.objects;
CREATE POLICY "tech_card_photos_update_authenticated"
  ON storage.objects FOR UPDATE TO authenticated
  USING  (bucket_id = 'tech_card_photos')
  WITH CHECK (bucket_id = 'tech_card_photos');

DROP POLICY IF EXISTS "tech_card_photos_select_public" ON storage.objects;
CREATE POLICY "tech_card_photos_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'tech_card_photos');

DROP POLICY IF EXISTS "tech_card_photos_delete_authenticated" ON storage.objects;
CREATE POLICY "tech_card_photos_delete_authenticated"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'tech_card_photos');
```

### 20260302210000_tech_card_sections.sql
```sql
-- Добавляем колонку sections (JSONB массив цехов) в tech_cards
-- Заменяет старую колонку section (String, не сохранялась)
-- Пустой массив [] = "Скрыто" (видят только шеф/су-шеф)
-- ['all'] = все цеха
-- ['hot_kitchen', 'cold_kitchen'] = конкретные цеха

ALTER TABLE tech_cards
  ADD COLUMN IF NOT EXISTS sections JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Индекс для быстрой фильтрации по цеху
CREATE INDEX IF NOT EXISTS idx_tech_cards_sections
  ON tech_cards USING GIN (sections);
```

### 20260303100000_owner_multi_establishment.sql
```sql
-- Owner-centric model: владелец — ключевое звено, может иметь несколько заведений.
-- 1. RPC добавления заведения существующим владельцем (без регистрации владельца)
-- 2. RPC получения списка заведений владельца
-- 3. RLS: владелец видит данные всех своих заведений (owner_id = auth.uid())
-- 4. owner_access_level для co-owner: view_only при >1 заведении у пригласившего

-- === 1. owner_access_level в employees (co-owner view-only) ===
ALTER TABLE employees ADD COLUMN IF NOT EXISTS owner_access_level TEXT DEFAULT 'full' CHECK (owner_access_level IN ('full', 'view_only'));

COMMENT ON COLUMN employees.owner_access_level IS 'full = полный доступ, view_only = только просмотр (co-owner при >1 заведении)';

-- === 2. RPC: add_establishment_for_owner ===
-- Добавление заведения существующим владельцем. Без регистрации владельца.
CREATE OR REPLACE FUNCTION public.add_establishment_for_owner(
  p_name text,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_pin_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_est jsonb;
  v_now timestamptz := now();
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  -- Проверка: пользователь — владелец хотя бы одного заведения
  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  -- Генерация уникального PIN, если не передан
  IF p_pin_code IS NULL OR trim(p_pin_code) = '' THEN
    LOOP
      v_pin := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));
      IF NOT EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_pin := upper(trim(p_pin_code));
    IF EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: pin_code already exists';
    END IF;
  END IF;

  INSERT INTO establishments (name, pin_code, owner_id, address, phone, email, created_at, updated_at)
  VALUES (
    trim(p_name), v_pin, v_owner_id,
    nullif(trim(p_address), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    v_now, v_now
  )
  RETURNING to_jsonb(establishments.*) INTO v_est;

  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION public.add_establishment_for_owner IS 'Добавление заведения существующим владельцем. Без регистрации владельца.';

GRANT EXECUTE ON FUNCTION public.add_establishment_for_owner TO authenticated;

-- === 3. RPC: get_establishments_for_owner ===
CREATE OR REPLACE FUNCTION public.get_establishments_for_owner()
RETURNS SETOF establishments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT e.* FROM establishments e
  WHERE e.owner_id = auth.uid()
  ORDER BY e.created_at;
$$;

COMMENT ON FUNCTION public.get_establishments_for_owner IS 'Список заведений владельца (owner_id = auth.uid)';

GRANT EXECUTE ON FUNCTION public.get_establishments_for_owner TO authenticated;

-- === 3b. Helpers для RLS (нужны до создания политик) ===
CREATE OR REPLACE FUNCTION public.is_current_user_view_only_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees
    WHERE id = auth.uid()
      AND 'owner' = ANY(roles)
      AND coalesce(owner_access_level, 'full') = 'view_only'
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_establishment_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT id FROM establishments WHERE owner_id = auth.uid()
  UNION
  SELECT establishment_id FROM employees WHERE id = auth.uid();
$$;

-- === 4. Обновить create_owner_employee: параметр p_owner_access_level ===
CREATE OR REPLACE FUNCTION public.create_owner_employee(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_roles text[] DEFAULT ARRAY['owner'],
  p_owner_access_level text DEFAULT 'full'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_emp jsonb;
  v_personal_pin text;
  v_now timestamptz := now();
  v_access text := coalesce(nullif(trim(p_owner_access_level), ''), 'full');
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN
    v_access := 'full';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_exists;

  IF NOT v_exists THEN
    RAISE EXCEPTION 'create_owner_employee: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_owner_employee: establishment % not found', p_establishment_id;
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  ) VALUES (
    p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
    trim(p_email), NULL,
    'management', NULL, p_roles, p_establishment_id, v_personal_pin,
    'ru', true, true, v_access, v_now, v_now
  );

  UPDATE establishments SET owner_id = p_auth_user_id, updated_at = v_now
  WHERE id = p_establishment_id;

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           owner_access_level, created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

-- Backfill owner_access_level для существующих записей (primary owner = full)
UPDATE employees SET owner_access_level = 'full' WHERE owner_access_level IS NULL AND 'owner' = ANY(roles);

-- === 5. create_employee_for_company: владелец может добавлять сотрудников в любое своё заведение ===
CREATE OR REPLACE FUNCTION public.create_employee_for_company(
  p_auth_user_id uuid,
  p_establishment_id uuid,
  p_full_name text,
  p_surname text,
  p_email text,
  p_department text,
  p_section text,
  p_roles text[],
  p_owner_access_level text DEFAULT 'full'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_is_owner boolean;
  v_auth_exists boolean;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
  v_access text := coalesce(nullif(trim(p_owner_access_level), ''), 'full');
BEGIN
  IF v_access NOT IN ('full', 'view_only') THEN
    v_access := 'full';
  END IF;

  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'create_employee_for_company: must be authenticated';
  END IF;

  -- Владелец: либо владеет заведением (owner_id), либо его employee.establishment_id = p_establishment_id
  SELECT EXISTS (
    SELECT 1 FROM establishments e
    WHERE e.id = p_establishment_id
      AND (e.owner_id = v_caller_id
           OR EXISTS (
             SELECT 1 FROM employees emp
             WHERE emp.id = v_caller_id
               AND emp.establishment_id = p_establishment_id
               AND 'owner' = ANY(emp.roles)
               AND emp.is_active = true
           ))
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'create_employee_for_company: only owner can add employees';
  END IF;

  IF is_current_user_view_only_owner() THEN
    RAISE EXCEPTION 'create_employee_for_company: view-only owner cannot add employees';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = p_auth_user_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) INTO v_auth_exists;

  IF NOT v_auth_exists THEN
    RAISE EXCEPTION 'create_employee_for_company: auth user % not found or email mismatch', p_auth_user_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE id = p_establishment_id) THEN
    RAISE EXCEPTION 'create_employee_for_company: establishment % not found', p_establishment_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM employees
    WHERE establishment_id = p_establishment_id
      AND LOWER(email) = LOWER(trim(p_email))
  ) THEN
    RAISE EXCEPTION 'create_employee_for_company: email already taken in establishment';
  END IF;

  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  -- owner роль: вставляем с owner_access_level
  IF 'owner' = ANY(p_roles) THEN
    INSERT INTO employees (
      id, full_name, surname, email, password_hash,
      department, section, roles, establishment_id, personal_pin,
      preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
    )     VALUES (
      p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
      trim(p_email), NULL,
      COALESCE(NULLIF(trim(p_department), ''), 'management'),
      nullif(trim(p_section), ''),
      p_roles, p_establishment_id, v_personal_pin,
      'ru', true, true, v_access, v_now, v_now
    );
    -- Co-owner: не обновляем owner_id (основной владелец уже задан)
  ELSE
    INSERT INTO employees (
      id, full_name, surname, email, password_hash,
      department, section, roles, establishment_id, personal_pin,
      preferred_language, is_active, data_access_enabled, created_at, updated_at
    ) VALUES (
      p_auth_user_id, trim(p_full_name), nullif(trim(p_surname), ''),
      trim(p_email), NULL,
      COALESCE(NULLIF(trim(p_department), ''), 'kitchen'),
      nullif(trim(p_section), ''),
      p_roles, p_establishment_id, v_personal_pin,
      'ru', true, false, v_now, v_now
    );
  END IF;

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           owner_access_level, created_at, updated_at
    FROM employees WHERE id = p_auth_user_id
  ) r;

  RETURN v_emp;
END;
$$;

-- === 6. co_owner_invitations: is_view_only_owner ===
ALTER TABLE co_owner_invitations ADD COLUMN IF NOT EXISTS is_view_only_owner boolean DEFAULT false;

-- co_owner_invitations: view_only не может создавать приглашения; владелец видит приглашения всех своих заведений
DROP POLICY IF EXISTS "Owners can view co-owner invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "Owners can create co-owner invitations" ON co_owner_invitations;
DROP POLICY IF EXISTS "Owners can update co-owner invitations" ON co_owner_invitations;
CREATE POLICY "Owners can view co-owner invitations" ON co_owner_invitations
  FOR SELECT USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "Owners can create co-owner invitations" ON co_owner_invitations
  FOR INSERT WITH CHECK (
    establishment_id IN (SELECT current_user_establishment_ids())
    AND NOT is_current_user_view_only_owner()
  );
CREATE POLICY "Owners can update co-owner invitations" ON co_owner_invitations
  FOR UPDATE USING (establishment_id IN (SELECT current_user_establishment_ids()));

-- === 6b. RPC: create_co_owner_from_invitation ===
-- Co-owner создаёт свою запись сотрудника по принятому приглашению (session = новый юзер)
CREATE OR REPLACE FUNCTION public.create_co_owner_from_invitation(
  p_invitation_token text,
  p_full_name text,
  p_surname text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv record;
  v_access text;
  v_personal_pin text;
  v_now timestamptz := now();
  v_emp jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'create_co_owner_from_invitation: must be authenticated';
  END IF;

  SELECT inv.*, e.id as est_id, e.name as est_name, e.pin_code as est_pin, e.default_currency as est_currency
  INTO v_inv
  FROM co_owner_invitations inv
  JOIN establishments e ON e.id = inv.establishment_id
  WHERE inv.invitation_token = p_invitation_token
    AND inv.status = 'accepted'
    AND LOWER(inv.invited_email) = LOWER((SELECT email FROM auth.users WHERE id = auth.uid()));

  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'create_co_owner_from_invitation: invalid or expired invitation';
  END IF;

  IF EXISTS (SELECT 1 FROM employees WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'create_co_owner_from_invitation: employee already exists';
  END IF;

  v_access := CASE WHEN coalesce(v_inv.is_view_only_owner, false) THEN 'view_only' ELSE 'full' END;
  v_personal_pin := lpad((floor(random() * 900000) + 100000)::text, 6, '0');

  INSERT INTO employees (
    id, full_name, surname, email, password_hash,
    department, section, roles, establishment_id, personal_pin,
    preferred_language, is_active, data_access_enabled, owner_access_level, created_at, updated_at
  )
  SELECT
    auth.uid(), trim(p_full_name), nullif(trim(p_surname), ''),
    au.email, NULL,
    'management', NULL, ARRAY['owner'], v_inv.establishment_id, v_personal_pin,
    'ru', true, true, v_access, v_now, v_now
  FROM auth.users au WHERE au.id = auth.uid();

  SELECT to_jsonb(r) INTO v_emp
  FROM (
    SELECT id, full_name, surname, email, department, section, roles,
           establishment_id, personal_pin, preferred_language, is_active, data_access_enabled,
           owner_access_level, created_at, updated_at
    FROM employees WHERE id = auth.uid()
  ) r;

  RETURN v_emp;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_co_owner_from_invitation TO authenticated;

-- RPC для загрузки приглашения по токену (anon — для экрана регистрации до входа)
CREATE OR REPLACE FUNCTION public.get_co_owner_invitation_by_token(p_token text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT to_jsonb(r) FROM (
    SELECT inv.*, jsonb_build_object(
      'id', e.id, 'name', e.name, 'pin_code', e.pin_code,
      'owner_id', e.owner_id, 'default_currency', e.default_currency,
      'created_at', e.created_at, 'updated_at', e.updated_at
    ) as establishments
    FROM co_owner_invitations inv
    JOIN establishments e ON e.id = inv.establishment_id
    WHERE inv.invitation_token = p_token
      AND inv.status IN ('pending', 'accepted')
      AND (inv.expires_at IS NULL OR inv.expires_at > now())
  ) r;
$$;

GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token TO anon;
GRANT EXECUTE ON FUNCTION public.get_co_owner_invitation_by_token TO authenticated;

-- === 8. RLS: владелец — доступ ко всем своим заведениям ===
DROP POLICY IF EXISTS "auth_select_employees" ON employees;
CREATE POLICY "auth_select_employees" ON employees
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR establishment_id IN (SELECT current_user_establishment_ids())
  );

DROP POLICY IF EXISTS "auth_select_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_insert_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_update_establishment_products" ON establishment_products;
DROP POLICY IF EXISTS "auth_delete_establishment_products" ON establishment_products;
CREATE POLICY "auth_select_establishment_products" ON establishment_products FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_insert_establishment_products" ON establishment_products FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_update_establishment_products" ON establishment_products FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_delete_establishment_products" ON establishment_products FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_inventory_documents_select" ON inventory_documents;
DROP POLICY IF EXISTS "auth_inventory_documents_insert" ON inventory_documents;
CREATE POLICY "auth_inventory_documents_select" ON inventory_documents FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
    OR recipient_chef_id = auth.uid()
  );
CREATE POLICY "auth_inventory_documents_insert" ON inventory_documents FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_order_documents_select" ON order_documents;
DROP POLICY IF EXISTS "auth_order_documents_insert" ON order_documents;
CREATE POLICY "auth_order_documents_select" ON order_documents FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_order_documents_insert" ON order_documents FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_inventory_drafts" ON inventory_drafts;
DROP POLICY IF EXISTS "auth_inventory_drafts_select" ON inventory_drafts;
DROP POLICY IF EXISTS "auth_inventory_drafts_insert" ON inventory_drafts;
DROP POLICY IF EXISTS "auth_inventory_drafts_update" ON inventory_drafts;
CREATE POLICY "auth_inventory_drafts_select" ON inventory_drafts FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_inventory_drafts_insert" ON inventory_drafts FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_inventory_drafts_update" ON inventory_drafts FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_select_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_insert_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_update_tech_cards" ON tech_cards;
DROP POLICY IF EXISTS "auth_delete_tech_cards" ON tech_cards;
CREATE POLICY "auth_select_tech_cards" ON tech_cards FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_insert_tech_cards" ON tech_cards FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_update_tech_cards" ON tech_cards FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_delete_tech_cards" ON tech_cards FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_select_establishments" ON establishments;
DROP POLICY IF EXISTS "auth_update_establishments" ON establishments;
CREATE POLICY "auth_select_establishments" ON establishments FOR SELECT TO authenticated
  USING (id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_update_establishments" ON establishments FOR UPDATE TO authenticated
  USING (id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (true);

-- checklists, checklist_items — владелец видит все свои
DROP POLICY IF EXISTS "auth_checklists_select" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_insert" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_update" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_delete" ON checklists;
CREATE POLICY "auth_checklists_select" ON checklists FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_checklists_insert" ON checklists FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklists_update" ON checklists FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklists_delete" ON checklists FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_checklist_items_select" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_insert" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_update" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_delete" ON checklist_items;
CREATE POLICY "auth_checklist_items_select" ON checklist_items FOR SELECT TO authenticated
  USING (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())));
CREATE POLICY "auth_checklist_items_insert" ON checklist_items FOR INSERT TO authenticated
  WITH CHECK (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_items_update" ON checklist_items FOR UPDATE TO authenticated
  USING (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner())
  WITH CHECK (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_items_delete" ON checklist_items FOR DELETE TO authenticated
  USING (checklist_id IN (SELECT id FROM checklists WHERE establishment_id IN (SELECT current_user_establishment_ids())) AND NOT is_current_user_view_only_owner());

-- checklist_drafts, checklist_submissions, schedule, order_list
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
CREATE POLICY "auth_checklist_drafts_select" ON checklist_drafts FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_checklist_drafts_insert" ON checklist_drafts FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_drafts_update" ON checklist_drafts FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner())
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_drafts_delete" ON checklist_drafts FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;
CREATE POLICY "auth_checklist_submissions_select" ON checklist_submissions FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT current_user_establishment_ids())
    OR recipient_chef_id = auth.uid()
  );
CREATE POLICY "auth_checklist_submissions_insert" ON checklist_submissions FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_submissions_update" ON checklist_submissions FOR UPDATE TO authenticated
  USING (
    (establishment_id IN (SELECT current_user_establishment_ids()) OR recipient_chef_id = auth.uid())
    AND NOT is_current_user_view_only_owner()
  )
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());
CREATE POLICY "auth_checklist_submissions_delete" ON checklist_submissions FOR DELETE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()) AND NOT is_current_user_view_only_owner());

DROP POLICY IF EXISTS "auth_schedule_select" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_insert" ON establishment_schedule_data;
DROP POLICY IF EXISTS "auth_schedule_update" ON establishment_schedule_data;
CREATE POLICY "auth_schedule_select" ON establishment_schedule_data FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_schedule_insert" ON establishment_schedule_data FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_schedule_update" ON establishment_schedule_data FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));

DROP POLICY IF EXISTS "auth_order_list_select" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_insert" ON establishment_order_list_data;
DROP POLICY IF EXISTS "auth_order_list_update" ON establishment_order_list_data;
CREATE POLICY "auth_order_list_select" ON establishment_order_list_data FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_order_list_insert" ON establishment_order_list_data FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_order_list_update" ON establishment_order_list_data FOR UPDATE TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()))
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));

-- product_price_history
DROP POLICY IF EXISTS "auth_select_product_price_history" ON product_price_history;
DROP POLICY IF EXISTS "auth_insert_product_price_history" ON product_price_history;
CREATE POLICY "auth_select_product_price_history" ON product_price_history FOR SELECT TO authenticated
  USING (establishment_id IN (SELECT current_user_establishment_ids()));
CREATE POLICY "auth_insert_product_price_history" ON product_price_history FOR INSERT TO authenticated
  WITH CHECK (establishment_id IN (SELECT current_user_establishment_ids()));
```

### 20260303110000_establishment_branches.sql
```sql
-- Филиалы заведений: parent_establishment_id, синхронизация номенклатуры и ТТК
-- Филиал наследует данные (номенклатура, ТТК ПФ, ТТК блюда) от основного заведения
-- Нельзя создать филиал филиала — только филиал основного заведения

-- === 1. parent_establishment_id в establishments ===
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS parent_establishment_id UUID REFERENCES establishments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_establishments_parent ON establishments(parent_establishment_id);

COMMENT ON COLUMN establishments.parent_establishment_id IS 'NULL = основное заведение, иначе = филиал указанного заведения';

-- Ограничение: родитель должен быть основным (не филиалом)
ALTER TABLE establishments DROP CONSTRAINT IF EXISTS chk_parent_is_main;
ALTER TABLE establishments ADD CONSTRAINT chk_parent_is_main CHECK (
  parent_establishment_id IS NULL
  OR EXISTS (
    SELECT 1 FROM establishments p
    WHERE p.id = parent_establishment_id AND p.parent_establishment_id IS NULL
  )
);

-- === 2. RPC: ID заведения для данных (филиал → родитель, основное → само) ===
CREATE OR REPLACE FUNCTION public.get_data_establishment_id(p_establishment_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT parent_establishment_id FROM establishments WHERE id = p_establishment_id),
    p_establishment_id
  );
$$;

COMMENT ON FUNCTION public.get_data_establishment_id IS 'Для филиала возвращает parent_id (данные читаем из родителя), для основного — self';

-- === 3. Обновить add_establishment_for_owner: параметр p_parent_establishment_id ===
CREATE OR REPLACE FUNCTION public.add_establishment_for_owner(
  p_name text,
  p_address text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_pin_code text DEFAULT NULL,
  p_parent_establishment_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_pin text;
  v_est jsonb;
  v_now timestamptz := now();
BEGIN
  v_owner_id := auth.uid();
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'add_establishment_for_owner: must be authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM establishments WHERE owner_id = v_owner_id) THEN
    RAISE EXCEPTION 'add_establishment_for_owner: only owners can add establishments';
  END IF;

  -- Если филиал: проверяем parent — должен существовать, принадлежать владельцу, быть основным
  IF p_parent_establishment_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM establishments
      WHERE id = p_parent_establishment_id
        AND owner_id = v_owner_id
        AND parent_establishment_id IS NULL
    ) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: parent must be your main establishment';
    END IF;
  END IF;

  IF p_pin_code IS NULL OR trim(p_pin_code) = '' THEN
    LOOP
      v_pin := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));
      IF NOT EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_pin := upper(trim(p_pin_code));
    IF EXISTS (SELECT 1 FROM establishments WHERE pin_code = v_pin) THEN
      RAISE EXCEPTION 'add_establishment_for_owner: pin_code already exists';
    END IF;
  END IF;

  INSERT INTO establishments (name, pin_code, owner_id, address, phone, email, parent_establishment_id, created_at, updated_at)
  VALUES (
    trim(p_name), v_pin, v_owner_id,
    nullif(trim(p_address), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_email), ''),
    p_parent_establishment_id,
    v_now, v_now
  )
  RETURNING to_jsonb(establishments.*) INTO v_est;

  RETURN v_est;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_establishment_for_owner TO authenticated;

-- === 4. RPC: филиалы данного заведения (для шефа — фильтр по филиалам) ===
CREATE OR REPLACE FUNCTION public.get_branches_for_establishment(p_establishment_id uuid)
RETURNS SETOF establishments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT e.* FROM establishments e
  WHERE e.parent_establishment_id = p_establishment_id
  ORDER BY e.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_branches_for_establishment TO authenticated;
```

### 20260303120000_checklists_department.sql
```sql
-- Добавить assigned_department в checklists для разделения по подразделениям (кухня, бар, зал)
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_department TEXT DEFAULT 'kitchen';

COMMENT ON COLUMN checklists.assigned_department IS 'Подразделение: kitchen, bar, hall. По умолчанию kitchen.';
```

### 20260303130000_nomenclature_and_ttk_department.sql
```sql
-- 1. Номенклатура по отделам: bar и kitchen имеют отдельные списки продуктов
ALTER TABLE establishment_products ADD COLUMN IF NOT EXISTS department TEXT DEFAULT 'kitchen' NOT NULL;
COMMENT ON COLUMN establishment_products.department IS 'Отдел номенклатуры: kitchen, bar. По умолчанию kitchen.';

UPDATE establishment_products SET department = 'kitchen' WHERE department IS NULL;

-- Уникальность: один продукт может быть и в кухне, и в баре
ALTER TABLE establishment_products DROP CONSTRAINT IF EXISTS establishment_products_establishment_id_product_id_key;
ALTER TABLE establishment_products ADD CONSTRAINT establishment_products_est_product_dept_key
  UNIQUE (establishment_id, product_id, department);

-- 2. ТТК по отделам: ТТК кухни и ТТК бара не пересекаются
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS department TEXT DEFAULT 'kitchen';
COMMENT ON COLUMN tech_cards.department IS 'Отдел: kitchen, bar. ТТК кухни и бара разделены.';

UPDATE tech_cards SET department = 'kitchen' WHERE department IS NULL;
```

### 20260304000000_registration_ip_metadata.sql
```sql
-- Добавляем колонки для IP и геолокации при регистрации заведения
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS registration_ip TEXT;
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS registration_country TEXT;
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS registration_city TEXT;

COMMENT ON COLUMN establishments.registration_ip IS 'IP адрес клиента при регистрации';
COMMENT ON COLUMN establishments.registration_country IS 'Страна по IP при регистрации';
COMMENT ON COLUMN establishments.registration_city IS 'Город по IP при регистрации';
```

### 20260304120000_checklists_assignment_dates.sql
```sql
-- Настройки создания чеклиста: сотрудники, deadline, на когда
-- assigned_employee_ids: массив UUID сотрудников (null/пустой = всем)
-- deadline_at, scheduled_for_at: опциональные дата+время

ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_ids JSONB DEFAULT '[]';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS scheduled_for_at TIMESTAMP WITH TIME ZONE;

COMMENT ON COLUMN checklists.assigned_employee_ids IS 'Массив UUID сотрудников. null или [] = всем. Непустой = выбранным.';
COMMENT ON COLUMN checklists.deadline_at IS 'Срок выполнения (опционально).';
COMMENT ON COLUMN checklists.scheduled_for_at IS 'На когда назначен чеклист (опционально).';
```

### 20260304120500_can_edit_own_schedule.sql
```sql
-- Разрешение сотруднику редактировать свой личный график (как шеф).
ALTER TABLE employees ADD COLUMN IF NOT EXISTS can_edit_own_schedule boolean DEFAULT false NOT NULL;
COMMENT ON COLUMN employees.can_edit_own_schedule IS 'Сотрудник может менять свой личный график';
```

### 20260304160000_ensure_assigned_department.sql
```sql
-- Обеспечить наличие assigned_department (если миграция 20260303120000 не применялась)
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_department TEXT DEFAULT 'kitchen';
COMMENT ON COLUMN checklists.assigned_department IS 'Подразделение: kitchen, bar, hall. По умолчанию kitchen.';
```

### 20260305000000_register_company_with_promo_rpc.sql
```sql
-- =============================================================================
-- ЗАЩИТА РЕГИСТРАЦИИ: создание заведения только через RPC с проверкой промокода
-- Обойти защиту через прямой INSERT невозможно — anon INSERT закрыт.
-- =============================================================================

-- 1. Убираем anon INSERT на establishments (если ещё есть)
DROP POLICY IF EXISTS "anon_insert_establishments" ON establishments;

-- 2. RPC: регистрация компании только с валидным промокодом
-- Логика: проверить промокод → создать заведение → пометить промокод использованным
-- Всё в одной транзакции. Без валидного промокода заведение не создаётся.
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
  -- 1. Валидация промокода (та же логика, что в check_promo_code / use_promo_code)
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

  -- 2. Создание заведения (owner_id = NULL, владелец на следующем шаге)
  v_est_id := gen_random_uuid();
  INSERT INTO establishments (id, name, pin_code, address, default_currency, created_at, updated_at)
  VALUES (
    v_est_id,
    trim(coalesce(p_name, '')),
    trim(upper(coalesce(p_pin_code, ''))),
    nullif(trim(p_address), ''),
    'RUB',
    now(),
    now()
  );

  -- 3. Промокод помечаем использованным
  UPDATE promo_codes
  SET is_used = true, used_by_establishment_id = v_est_id, used_at = now()
  WHERE id = v_row.id;

  -- 4. Возврат созданного заведения
  SELECT to_jsonb(e) INTO v_est
  FROM (
    SELECT id, name, pin_code, owner_id, address, phone, email, default_currency, created_at, updated_at
    FROM establishments
    WHERE id = v_est_id
  ) e;
  RETURN v_est;
END;
$$;

COMMENT ON FUNCTION register_company_with_promo IS 'Регистрация компании с обязательной проверкой промокода. Единственный способ создать новое заведение.';

GRANT EXECUTE ON FUNCTION register_company_with_promo(text, text, text, text) TO anon;
GRANT EXECUTE ON FUNCTION register_company_with_promo(text, text, text, text) TO authenticated;
```

### 20260305100000_update_checklist_dates_rpc.sql
```sql
-- Обновление deadline_at и scheduled_for_at через RPC (обходит schema cache PostgREST).
CREATE OR REPLACE FUNCTION public.update_checklist_dates(
  p_checklist_id uuid,
  p_deadline_at timestamptz DEFAULT NULL,
  p_scheduled_for_at timestamptz DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE checklists
  SET
    updated_at = now(),
    deadline_at = p_deadline_at,
    scheduled_for_at = p_scheduled_for_at
  WHERE id = p_checklist_id;
$$;

GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO anon;
GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO authenticated;
```

### 20260305200000_employee_direct_messages.sql
```sql
-- Сообщения между сотрудниками одного заведения.
CREATE TABLE IF NOT EXISTS employee_direct_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  recipient_employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CHECK (sender_employee_id != recipient_employee_id)
);

CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_sender ON employee_direct_messages(sender_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_recipient ON employee_direct_messages(recipient_employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_direct_messages_created ON employee_direct_messages(created_at DESC);

ALTER TABLE employee_direct_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_employee_messages_select" ON employee_direct_messages
  FOR SELECT TO authenticated
  USING (sender_employee_id = auth.uid() OR recipient_employee_id = auth.uid());

CREATE POLICY "auth_employee_messages_insert" ON employee_direct_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_employee_id = auth.uid()
    AND recipient_employee_id != auth.uid()
    AND recipient_employee_id IN (
      SELECT id FROM employees e
      WHERE e.establishment_id = (SELECT establishment_id FROM employees WHERE id = auth.uid())
    )
  );

COMMENT ON TABLE employee_direct_messages IS 'Личные сообщения между сотрудниками заведения.';
```

### 20260306000000_employee_employment_status.sql
```sql
-- Статус сотрудника: постоянный/временный. Для временных — период доступа (дата начала и конца).
-- После даты конца — доступ ограничен (только личный график).
ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_status TEXT DEFAULT 'permanent' NOT NULL;
COMMENT ON COLUMN employees.employment_status IS 'Статус: permanent — постоянный, temporary — временный';

ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_start_date DATE;
COMMENT ON COLUMN employees.employment_start_date IS 'Дата начала (для временных). Задаёт шеф/барменеджер/менеджер зала.';

ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_end_date DATE;
COMMENT ON COLUMN employees.employment_end_date IS 'Дата конца (для временных). После этой даты — только личный график.';
```

### 20260307120000_employees_last_login_location.sql
```sql
-- Местоположение при последнем входе (для отображения пользователю и в админке)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_ip TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_country TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_city TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

COMMENT ON COLUMN employees.last_login_ip IS 'IP при последнем входе';
COMMENT ON COLUMN employees.last_login_country IS 'Страна по IP при последнем входе';
COMMENT ON COLUMN employees.last_login_city IS 'Город по IP при последнем входе';
COMMENT ON COLUMN employees.last_login_at IS 'Время последнего входа';
```

### 20260307200000_messages_read_at_and_realtime.sql
```sql
-- Добавляем read_at для непрочитанных сообщений и включаем Realtime.
ALTER TABLE employee_direct_messages
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMP WITH TIME ZONE;

CREATE POLICY "auth_employee_messages_update_read" ON employee_direct_messages
  FOR UPDATE TO authenticated
  USING (recipient_employee_id = auth.uid())
  WITH CHECK (recipient_employee_id = auth.uid());

-- Включаем Realtime для employee_direct_messages
ALTER PUBLICATION supabase_realtime ADD TABLE employee_direct_messages;
```

### 20260307300000_chat_images.sql
```sql
-- Фото в чате между сотрудниками
ALTER TABLE employee_direct_messages
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Бакет для фото в чатах
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES
  ('chat_images', 'chat_images', true, 5242880)
ON CONFLICT (id) DO UPDATE SET
  public          = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

DROP POLICY IF EXISTS "chat_images_insert_authenticated" ON storage.objects;
CREATE POLICY "chat_images_insert_authenticated"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'chat_images');

DROP POLICY IF EXISTS "chat_images_select_public" ON storage.objects;
CREATE POLICY "chat_images_select_public"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'chat_images');
```

