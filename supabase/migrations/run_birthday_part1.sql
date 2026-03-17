-- Part 1: column + table + RLS (run this first in Supabase SQL Editor)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS birthday date;
COMMENT ON COLUMN employees.birthday IS 'День рождения сотрудника (при регистрации/в профиле).';

CREATE TABLE IF NOT EXISTS employee_birthday_change_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  employee_name text NOT NULL,
  previous_birthday date,
  new_birthday date NOT NULL,
  changed_by_employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_employee_birthday_change_notifications_establishment
  ON employee_birthday_change_notifications(establishment_id);

CREATE INDEX IF NOT EXISTS idx_employee_birthday_change_notifications_created
  ON employee_birthday_change_notifications(created_at DESC);

ALTER TABLE employee_birthday_change_notifications ENABLE ROW LEVEL SECURITY;
