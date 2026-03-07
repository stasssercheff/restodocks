-- =============================================================================
-- Миграции (ранее для staging; Staging Supabase удалён — одна БД Prod)
-- Выполнить в Supabase Dashboard → SQL Editor (если применимо)
-- После выполнения: Settings → General → Restart project (обновит schema cache)
-- =============================================================================

-- 1. CHECKLISTS: assigned_department, assigned_section, assigned_employee_id
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_department TEXT DEFAULT 'kitchen';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_section TEXT;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
COMMENT ON COLUMN checklists.assigned_department IS 'Подразделение: kitchen, bar, hall.';

-- 2. CHECKLISTS: deadline_at, scheduled_for_at, assigned_employee_ids
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS assigned_employee_ids JSONB DEFAULT '[]';
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE checklists ADD COLUMN IF NOT EXISTS scheduled_for_at TIMESTAMP WITH TIME ZONE;

-- 3. CHECKLIST_ITEMS: tech_card_id, target_quantity, target_unit
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS tech_card_id UUID REFERENCES tech_cards(id) ON DELETE SET NULL;
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS target_quantity numeric(10, 3);
ALTER TABLE checklist_items ADD COLUMN IF NOT EXISTS target_unit text;

-- 4. RPC update_checklist_dates (обходит schema cache PostgREST)
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

-- 4b. CHECKLIST_SUBMISSIONS: filled_by_employee_id (приложение пишет эту колонку)
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS filled_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS submitted_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS recipient_chef_id UUID REFERENCES employees(id) ON DELETE SET NULL;
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS checklist_name TEXT DEFAULT '';
ALTER TABLE checklist_submissions ADD COLUMN IF NOT EXISTS section TEXT;
DO $$ BEGIN
  ALTER TABLE checklist_submissions ALTER COLUMN recipient_chef_id DROP NOT NULL;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
UPDATE checklist_submissions SET filled_by_employee_id = submitted_by_employee_id WHERE filled_by_employee_id IS NULL AND submitted_by_employee_id IS NOT NULL;

-- 5. EMPLOYEE DIRECT MESSAGES (таблица для личных сообщений)
--    ⚠️ После выполнения: Settings → General → Restart project
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

DROP POLICY IF EXISTS "auth_employee_messages_select" ON employee_direct_messages;
CREATE POLICY "auth_employee_messages_select" ON employee_direct_messages
  FOR SELECT TO authenticated
  USING (sender_employee_id = auth.uid() OR recipient_employee_id = auth.uid());

DROP POLICY IF EXISTS "auth_employee_messages_insert" ON employee_direct_messages;
CREATE POLICY "auth_employee_messages_insert" ON employee_direct_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_employee_id = auth.uid()
    AND recipient_employee_id != auth.uid()
    AND recipient_employee_id IN (
      SELECT e.id FROM employees e
      WHERE e.establishment_id = (SELECT establishment_id FROM employees WHERE id = auth.uid())
    )
  );

GRANT SELECT, INSERT ON employee_direct_messages TO authenticated;

-- 5b. TECH_CARDS: description_for_hall, composition_for_hall (для меню зала)
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS description_for_hall TEXT;
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS composition_for_hall TEXT;
COMMENT ON COLUMN tech_cards.description_for_hall IS 'Описание блюда для гостей (меню зала)';
COMMENT ON COLUMN tech_cards.composition_for_hall IS 'Состав блюда для гостей (меню зала)';

-- 6. EMPLOYEE: employment_status (постоянный/временный)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_status TEXT DEFAULT 'permanent';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_start_date DATE;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS employment_end_date DATE;
