-- Уведомления об удалении сотрудников + RPC delete_employee_by_manager
-- Руководители (owner, шеф, су-шеф, менеджер зала, барменеджер) видят эти уведомления во входящих.

-- Таблица уведомлений об удалении сотрудников
CREATE TABLE IF NOT EXISTS employee_deletion_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  deleted_employee_id uuid NOT NULL,
  deleted_employee_name text NOT NULL,
  deleted_employee_email text,
  deleted_by_employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  deleted_by_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_employee_deletion_notifications_establishment
  ON employee_deletion_notifications(establishment_id);
CREATE INDEX IF NOT EXISTS idx_employee_deletion_notifications_created
  ON employee_deletion_notifications(created_at DESC);

ALTER TABLE employee_deletion_notifications ENABLE ROW LEVEL SECURITY;

-- RLS: только сотрудники заведения (owner, executive_chef, sous_chef, bar_manager, floor_manager) видят уведомления
CREATE POLICY "auth_select_employee_deletion_notifications" ON employee_deletion_notifications
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT establishment_id FROM employees
      WHERE id = auth.uid()
        AND (roles @> ARRAY['owner'] OR roles @> ARRAY['executive_chef'] OR roles @> ARRAY['sous_chef']
             OR roles @> ARRAY['bar_manager'] OR roles @> ARRAY['floor_manager'])
    )
  );

-- INSERT выполняется только через Edge Function (service_role), RLS для INSERT не нужен
-- SELECT — только для руководителей (см. политику выше)

COMMENT ON TABLE employee_deletion_notifications IS 'Уведомления об удалении сотрудников. Показываются руководителям во вкладке Уведомления.';
