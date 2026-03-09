-- Stop-list / Go-list: отметки блюд в меню кухни и бара.
-- Кухня и бар отмечают блюда stop (не продавать) или go (акцент).
-- Сотрудники зала видят подсвеченные названия в меню.

CREATE TABLE IF NOT EXISTS menu_stop_go (
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  tech_card_id UUID NOT NULL REFERENCES tech_cards(id) ON DELETE CASCADE,
  department TEXT NOT NULL CHECK (department IN ('kitchen', 'bar')),
  status TEXT NOT NULL CHECK (status IN ('stop', 'go')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (establishment_id, tech_card_id, department)
);

CREATE INDEX IF NOT EXISTS idx_menu_stop_go_establishment ON menu_stop_go(establishment_id);
CREATE INDEX IF NOT EXISTS idx_menu_stop_go_tech_card ON menu_stop_go(tech_card_id);

COMMENT ON TABLE menu_stop_go IS 'Stop-list и Go-list: статус блюда в меню кухни/бара для отображения сотрудникам зала';

-- RLS
ALTER TABLE menu_stop_go ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_select_menu_stop_go" ON menu_stop_go;
CREATE POLICY "auth_select_menu_stop_go" ON menu_stop_go FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "auth_insert_menu_stop_go" ON menu_stop_go;
CREATE POLICY "auth_insert_menu_stop_go" ON menu_stop_go FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "auth_update_menu_stop_go" ON menu_stop_go;
CREATE POLICY "auth_update_menu_stop_go" ON menu_stop_go FOR UPDATE TO authenticated
  USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "auth_delete_menu_stop_go" ON menu_stop_go;
CREATE POLICY "auth_delete_menu_stop_go" ON menu_stop_go FOR DELETE TO authenticated
  USING (
    establishment_id IN (
      SELECT e.id FROM establishments e
      JOIN employees emp ON emp.establishment_id = e.id
      WHERE emp.auth_user_id = auth.uid()
    )
  );
