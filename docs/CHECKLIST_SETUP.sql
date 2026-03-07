-- =============================================================================
-- Настройка чеклистов: при создании и внесении данных не сохранялись
-- Выполнить в Supabase Dashboard → SQL Editor
-- После выполнения: Settings → General → Restart project (обновит schema cache)
--
-- Примечание: секции 1–4 могут быть уже применены из других миграций
-- могут быть частично применены. Скрипт использует IF NOT EXISTS / DROP IF EXISTS.
-- =============================================================================

-- 1. CHECKLISTS: недостающие колонки
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_department TEXT DEFAULT 'kitchen';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_section TEXT;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_ids JSONB DEFAULT '[]';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS scheduled_for_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS additional_name TEXT;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'tasks';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS action_config JSONB DEFAULT '{"has_numeric":false,"has_toggle":true}'::jsonb;

-- 2. CHECKLIST_ITEMS: недостающие колонки
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL;
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS target_quantity numeric(10, 3);
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS target_unit text;

-- 3. CHECKLIST_SUBMISSIONS: filled_by_employee_id — приложение пишет эту колонку, но она может отсутствовать
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS submitted_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS filled_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS recipient_chef_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS checklist_name TEXT DEFAULT '';
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS section TEXT;
ALTER TABLE checklist_submissions ALTER COLUMN recipient_chef_id DROP NOT NULL;

-- 4. CHECKLIST_DRAFTS: таблица для автосохранения заполнения (если нет)
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

-- 5. RPC update_checklist_dates (для сохранения дат)
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
  SET updated_at = now(), deadline_at = p_deadline_at, scheduled_for_at = p_scheduled_for_at
  WHERE id = p_checklist_id;
$$;
GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO anon;
GRANT EXECUTE ON FUNCTION public.update_checklist_dates(uuid, timestamptz, timestamptz) TO authenticated;

-- 6. RLS: checklists — INSERT/UPDATE/SELECT для сотрудников заведения
DROP POLICY IF EXISTS "anon_checklists_all" ON checklists;
DROP POLICY IF EXISTS "checklists_establishment_access" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_all" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_select" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_insert" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_update" ON checklists;
DROP POLICY IF EXISTS "auth_checklists_delete" ON checklists;

CREATE POLICY "auth_checklists_all" ON checklists
FOR ALL TO authenticated
USING (
  establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
)
WITH CHECK (
  establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
);

-- 7. RLS: checklist_items — через checklist
DROP POLICY IF EXISTS "anon_checklist_items_all" ON checklist_items;
DROP POLICY IF EXISTS "checklist_items_access" ON checklist_items;
DROP POLICY IF EXISTS "auth_checklist_items_all" ON checklist_items;
CREATE POLICY "auth_checklist_items_all" ON checklist_items
FOR ALL TO authenticated
USING (
  checklist_id IN (
    SELECT id FROM checklists WHERE establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
)
WITH CHECK (
  checklist_id IN (
    SELECT id FROM checklists WHERE establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()
    )
  )
);

-- 8. RLS: checklist_submissions — сотрудники могут создавать для своего заведения
DROP POLICY IF EXISTS "anon_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_all" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_select" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_insert" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_update" ON checklist_submissions;
DROP POLICY IF EXISTS "auth_checklist_submissions_delete" ON checklist_submissions;

CREATE POLICY "auth_checklist_submissions_all" ON checklist_submissions
FOR ALL TO authenticated
USING (
  establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  OR recipient_chef_id = auth.uid()
)
WITH CHECK (
  establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
);

-- 9. RLS: checklist_drafts — автосохранение заполнения
DROP POLICY IF EXISTS "anon_checklist_drafts" ON checklist_drafts;
DROP POLICY IF EXISTS "auth_checklist_drafts_all" ON checklist_drafts;
DROP POLICY IF EXISTS "auth_checklist_drafts_select" ON checklist_drafts;
DROP POLICY IF EXISTS "auth_checklist_drafts_insert" ON checklist_drafts;
DROP POLICY IF EXISTS "auth_checklist_drafts_update" ON checklist_drafts;
DROP POLICY IF EXISTS "auth_checklist_drafts_delete" ON checklist_drafts;

CREATE POLICY "auth_checklist_drafts_all" ON checklist_drafts
FOR ALL TO authenticated
USING (
  establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
)
WITH CHECK (
  establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
);

-- 10. Синхронизация filled_by_employee_id из submitted_by_employee_id (для старых строк)
UPDATE checklist_submissions
SET filled_by_employee_id = submitted_by_employee_id
WHERE filled_by_employee_id IS NULL
  AND submitted_by_employee_id IS NOT NULL;
