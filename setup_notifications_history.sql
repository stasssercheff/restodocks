-- ПОЛНАЯ НАСТРОЙКА СИСТЕМЫ УВЕДОМЛЕНИЙ И ИСТОРИИ

-- 1. ИСТОРИЯ ЗАКАЗОВ ПРОДУКТОВ
CREATE TABLE IF NOT EXISTS order_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  order_data JSONB NOT NULL,
  status VARCHAR(50) DEFAULT 'sent',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. ИСТОРИЯ ИНВЕНТАРИЗАЦИЙ
CREATE TABLE IF NOT EXISTS inventory_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  inventory_data JSONB NOT NULL,
  date DATE NOT NULL,
  start_time TIME,
  end_time TIME,
  total_items INTEGER DEFAULT 0,
  status VARCHAR(50) DEFAULT 'completed',
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. ЧЕРНОВИКИ ИНВЕНТАРИЗАЦИЙ (для автосохранения)
CREATE TABLE IF NOT EXISTS inventory_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  draft_data JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ИНДЕКСЫ ДЛЯ ПРОИЗВОДИТЕЛЬНОСТИ
CREATE INDEX IF NOT EXISTS idx_order_history_establishment ON order_history(establishment_id);
CREATE INDEX IF NOT EXISTS idx_order_history_employee ON order_history(employee_id);
CREATE INDEX IF NOT EXISTS idx_order_history_created ON order_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_history_status ON order_history(status);

CREATE INDEX IF NOT EXISTS idx_inventory_history_establishment ON inventory_history(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_history_employee ON inventory_history(employee_id);
CREATE INDEX IF NOT EXISTS idx_inventory_history_date ON inventory_history(date DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_history_created ON inventory_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inventory_history_status ON inventory_history(status);

CREATE INDEX IF NOT EXISTS idx_inventory_drafts_establishment ON inventory_drafts(establishment_id);
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_employee ON inventory_drafts(employee_id);
CREATE INDEX IF NOT EXISTS idx_inventory_drafts_updated ON inventory_drafts(updated_at DESC);

-- RLS ПОЛИТИКИ БЕЗОПАСНОСТИ
ALTER TABLE order_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_drafts ENABLE ROW LEVEL SECURITY;

-- ПОЛИТИКИ ДЛЯ ЗАКАЗОВ
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

-- ПОЛИТИКИ ДЛЯ ИНВЕНТАРИЗАЦИЙ
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

-- ПОЛИТИКИ ДЛЯ ЧЕРНОВИКОВ
CREATE POLICY "Users can manage their inventory drafts"
ON inventory_drafts FOR ALL USING (
  establishment_id IN (
    SELECT id FROM establishments WHERE owner_id = auth.uid()
  )
);

-- ФУНКЦИЯ ОЧИСТКИ СТАРЫХ ЗАПИСЕЙ
CREATE OR REPLACE FUNCTION cleanup_old_history()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Удаляем заказы старше 1 года
  DELETE FROM order_history WHERE created_at < NOW() - INTERVAL '1 year';

  -- Удаляем инвентаризации старше 2 лет
  DELETE FROM inventory_history WHERE created_at < NOW() - INTERVAL '2 years';

  -- Удаляем черновики старше 30 дней
  DELETE FROM inventory_drafts WHERE updated_at < NOW() - INTERVAL '30 days';
END;
$$;

-- КОММЕНТАРИИ
COMMENT ON TABLE order_history IS 'История отправленных заказов продуктов';
COMMENT ON TABLE inventory_history IS 'История заполненных инвентаризационных бланков';
COMMENT ON TABLE inventory_drafts IS 'Черновики инвентаризаций - автоматическое сохранение на сервер каждые 30 секунд';

-- ПРОВЕРКА СОЗДАНИЯ
SELECT
  'order_history' as table_name,
  COUNT(*) as records
FROM order_history
UNION ALL
SELECT
  'inventory_history' as table_name,
  COUNT(*) as records
FROM inventory_history
UNION ALL
SELECT
  'inventory_drafts' as table_name,
  COUNT(*) as records
FROM inventory_drafts;