-- Таблица поставщиков для заведения (название, контакты).
-- Выполнить в SQL Editor Supabase при необходимости.

CREATE TABLE IF NOT EXISTS suppliers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suppliers_establishment_id ON suppliers(establishment_id);

-- RLS: доступ только для своего заведения
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Suppliers select by establishment" ON suppliers;
CREATE POLICY "Suppliers select by establishment" ON suppliers
  FOR SELECT USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()::uuid
    )
  );

DROP POLICY IF EXISTS "Suppliers insert by establishment" ON suppliers;
CREATE POLICY "Suppliers insert by establishment" ON suppliers
  FOR INSERT WITH CHECK (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()::uuid
    )
  );

DROP POLICY IF EXISTS "Suppliers update by establishment" ON suppliers;
CREATE POLICY "Suppliers update by establishment" ON suppliers
  FOR UPDATE USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()::uuid
    )
  );

DROP POLICY IF EXISTS "Suppliers delete by establishment" ON suppliers;
CREATE POLICY "Suppliers delete by establishment" ON suppliers
  FOR DELETE USING (
    establishment_id IN (
      SELECT establishment_id FROM employees WHERE id = auth.uid()::uuid
    )
  );
