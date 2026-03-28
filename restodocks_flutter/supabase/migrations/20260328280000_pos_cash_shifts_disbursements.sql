-- Смены виртуальной кассы зала и выдача наличных по «нуждам».
CREATE TABLE IF NOT EXISTS pos_cash_shifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  opening_balance NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (opening_balance >= 0),
  closing_balance NUMERIC(14, 2),
  opened_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  closed_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pos_cash_one_open_shift
  ON pos_cash_shifts(establishment_id)
  WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pos_cash_shifts_est_started ON pos_cash_shifts(establishment_id, started_at DESC);

COMMENT ON TABLE pos_cash_shifts IS 'Смена кассы зала: остаток на начало/конец (для отчёта).';

ALTER TABLE pos_cash_shifts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_cash_shifts_all" ON pos_cash_shifts;
CREATE POLICY "anon_pos_cash_shifts_all" ON pos_cash_shifts
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_cash_shifts_all" ON pos_cash_shifts;
CREATE POLICY "auth_pos_cash_shifts_all" ON pos_cash_shifts
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS pos_cash_disbursements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  shift_id UUID REFERENCES pos_cash_shifts(id) ON DELETE SET NULL,
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  purpose TEXT NOT NULL,
  recipient_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  recipient_name TEXT,
  created_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pos_cash_disb_est ON pos_cash_disbursements(establishment_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_cash_disb_shift ON pos_cash_disbursements(shift_id);

COMMENT ON TABLE pos_cash_disbursements IS 'Выдача из кассы: поставщики, аванс, прочее (назначение в purpose).';

ALTER TABLE pos_cash_disbursements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_cash_disbursements_all" ON pos_cash_disbursements;
CREATE POLICY "anon_pos_cash_disbursements_all" ON pos_cash_disbursements
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_cash_disbursements_all" ON pos_cash_disbursements;
CREATE POLICY "auth_pos_cash_disbursements_all" ON pos_cash_disbursements
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
