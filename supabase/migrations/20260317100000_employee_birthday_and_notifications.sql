-- День рождения сотрудника + уведомления об изменении ДР (владелец и управление видят во входящих).

-- 1. Колонка birthday в employees (только дата, без времени)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS birthday date;

COMMENT ON COLUMN employees.birthday IS 'День рождения сотрудника (при регистрации/в профиле).';

-- 2. Таблица уведомлений об изменении дня рождения (при редактировании в профиле)
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

-- SELECT: собственник и сотрудники управления (как для employee_deletion_notifications + general_manager и отдел management)
CREATE POLICY "auth_select_employee_birthday_change_notifications" ON employee_birthday_change_notifications
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees
      WHERE id = auth.uid()
        AND (roles @> ARRAY['owner'] OR roles @> ARRAY['executive_chef'] OR roles @> ARRAY['sous_chef']
             OR roles @> ARRAY['bar_manager'] OR roles @> ARRAY['floor_manager'] OR roles @> ARRAY['general_manager']
             OR department = 'management')
    )
  );

-- INSERT: сотрудник может создать уведомление только о себе (employee_id = auth.uid())
CREATE POLICY "auth_insert_employee_birthday_change_own" ON employee_birthday_change_notifications
  FOR INSERT TO authenticated
  WITH CHECK (
    employee_id = auth.uid()
    AND changed_by_employee_id = auth.uid()
    AND establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid())
  );

COMMENT ON TABLE employee_birthday_change_notifications IS 'Уведомления об изменении дня рождения. Создаются при редактировании профиля. Видят владелец и управление во вкладке Уведомления.';
