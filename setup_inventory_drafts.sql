-- НАСТРОИТЬ СЕРВЕРНОЕ АВТОСОХРАНЕНИЕ ИНВЕНТАРИЗАЦИЙ

-- 1. Создать таблицу для черновиков
CREATE TABLE IF NOT EXISTS inventory_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Индексы
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_establishment
  ON inventory_drafts(establishment_id);

CREATE INDEX IF NOT EXISTS idx_inventory_drafts_employee
  ON inventory_drafts(employee_id);

CREATE INDEX IF NOT EXISTS idx_inventory_drafts_updated
  ON inventory_drafts(updated_at DESC);

-- 3. RLS политика
ALTER TABLE inventory_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage their inventory drafts" ON inventory_drafts;

CREATE POLICY "Users can manage their inventory drafts"
ON inventory_drafts FOR ALL USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- 4. Функция очистки старых черновиков
CREATE OR REPLACE FUNCTION cleanup_old_inventory_drafts()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM inventory_drafts
  WHERE updated_at < NOW() - INTERVAL '30 days';
END;
$$;

-- 5. Комментарий
COMMENT ON TABLE inventory_drafts IS 'Черновики инвентаризаций - автоматическое сохранение на сервер каждые 30 секунд';

-- 6. Проверить создание
SELECT
  schemaname,
  tablename,
  tableowner
FROM pg_tables
WHERE tablename = 'inventory_drafts';