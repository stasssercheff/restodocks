-- ИСТОРИЯ ИНВЕНТАРИЗАЦИЙ

CREATE TABLE IF NOT EXISTS inventory_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  inventory_data JSONB NOT NULL, -- Полные данные инвентаризации
  date DATE NOT NULL,
  start_time TIME,
  end_time TIME,
  total_items INTEGER DEFAULT 0,
  status VARCHAR(50) DEFAULT 'completed', -- draft, completed, sent
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_inventory_history_establishment
  ON inventory_history(establishment_id);

CREATE INDEX IF NOT EXISTS idx_inventory_history_employee
  ON inventory_history(employee_id);

CREATE INDEX IF NOT EXISTS idx_inventory_history_date
  ON inventory_history(date DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_history_created
  ON inventory_history(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_history_status
  ON inventory_history(status);

-- RLS политика
ALTER TABLE inventory_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view inventory history for their establishments"
ON inventory_history FOR SELECT USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

CREATE POLICY "Employees can create inventory records for their establishments"
ON inventory_history FOR INSERT WITH CHECK (
  establishment_id IN (
    SELECT e.id FROM establishments e
    JOIN employees emp ON e.id = emp.establishment_id
    WHERE emp.id = auth.uid()
  )
);

CREATE POLICY "Employees can update their inventory records"
ON inventory_history FOR UPDATE USING (
  employee_id = auth.uid() OR
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- Комментарий
COMMENT ON TABLE inventory_history IS 'История заполненных инвентаризационных бланков';