-- ИСТОРИЯ ЗАКАЗОВ ПРОДУКТОВ

CREATE TABLE IF NOT EXISTS order_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  order_data JSONB NOT NULL, -- Данные заказа (список продуктов, количества и т.д.)
  status VARCHAR(50) DEFAULT 'sent', -- sent, processing, completed, cancelled
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_order_history_establishment
  ON order_history(establishment_id);

CREATE INDEX IF NOT EXISTS idx_order_history_employee
  ON order_history(employee_id);

CREATE INDEX IF NOT EXISTS idx_order_history_created
  ON order_history(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_order_history_status
  ON order_history(status);

-- RLS политика
ALTER TABLE order_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view order history for their establishments"
ON order_history FOR SELECT USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

CREATE POLICY "Employees can create orders for their establishments"
ON order_history FOR INSERT WITH CHECK (
  establishment_id IN (
    SELECT e.id FROM establishments e
    JOIN employees emp ON e.id = emp.establishment_id
    WHERE emp.id = auth.uid()
  )
);

-- Комментарий
COMMENT ON TABLE order_history IS 'История отправленных заказов продуктов';