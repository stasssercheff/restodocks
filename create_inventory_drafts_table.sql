-- ТАБЛИЦА ДЛЯ АВТОМАТИЧЕСКОГО СОХРАНЕНИЯ ЧЕРНОВИКОВ ИНВЕНТАРИЗАЦИЙ НА СЕРВЕРЕ

CREATE TABLE IF NOT EXISTS inventory_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_establishment
  ON inventory_drafts(establishment_id);

CREATE INDEX IF NOT EXISTS idx_inventory_drafts_employee
  ON inventory_drafts(employee_id);

CREATE INDEX IF NOT EXISTS idx_inventory_drafts_updated
  ON inventory_drafts(updated_at DESC);

-- RLS политика: пользователь может видеть/обновлять только свои черновики
ALTER TABLE inventory_drafts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their inventory drafts"
ON inventory_drafts FOR ALL USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- Функция для автоматической очистки старых черновиков (старше 30 дней)
CREATE OR REPLACE FUNCTION cleanup_old_inventory_drafts()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM inventory_drafts
  WHERE updated_at < NOW() - INTERVAL '30 days';
END;
$$;

-- Комментарий
COMMENT ON TABLE inventory_drafts IS 'Черновики инвентаризаций для автоматического сохранения на сервер каждые 30 секунд';