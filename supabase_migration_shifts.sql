-- Дополнительные колонки для employees (если ещё нет)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS cost_per_unit REAL DEFAULT 0;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS payroll_counting_mode TEXT DEFAULT 'shift';

-- Дополнительные поля для продуктов и ТТК по подразделениям
ALTER TABLE products ADD COLUMN IF NOT EXISTS department TEXT DEFAULT 'kitchen';
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS department TEXT DEFAULT 'kitchen';

-- Таблица смен для Restodocks (миграция из Core Data)
CREATE TABLE IF NOT EXISTS shifts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date DATE NOT NULL,
  department TEXT,
  start_hour SMALLINT DEFAULT 0,
  end_hour SMALLINT DEFAULT 0,
  full_day BOOLEAN DEFAULT false,
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  confirmed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
);

-- Добавляем поле подтверждения смены (если таблица уже существует)
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_shifts_employee_id ON shifts(employee_id);
CREATE INDEX IF NOT EXISTS idx_shifts_date ON shifts(date);

-- RLS
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;

-- Удаляем существующие политики перед созданием новых
DROP POLICY IF EXISTS "Users can view shifts of their establishment" ON shifts;
DROP POLICY IF EXISTS "Users can insert shifts for their establishment" ON shifts;
DROP POLICY IF EXISTS "Users can update shifts of their establishment" ON shifts;
DROP POLICY IF EXISTS "Users can delete shifts of their establishment" ON shifts;

CREATE POLICY "Users can view shifts of their establishment"
  ON shifts FOR SELECT
  USING (
    employee_id IN (
      SELECT id FROM employees WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can insert shifts for their establishment"
  ON shifts FOR INSERT
  WITH CHECK (
    employee_id IN (
      SELECT id FROM employees WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can update shifts of their establishment"
  ON shifts FOR UPDATE
  USING (
    employee_id IN (
      SELECT id FROM employees WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can delete shifts of their establishment"
  ON shifts FOR DELETE
  USING (
    employee_id IN (
      SELECT id FROM employees WHERE establishment_id IN (
        SELECT establishment_id FROM employees WHERE id = auth.uid()
      )
    )
  );
