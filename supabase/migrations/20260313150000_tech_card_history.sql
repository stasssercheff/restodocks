-- История изменений ТТК (ПФ и блюд)
-- Фиксирует: что изменилось (продукт, количество, % отхода/ужарки, вес порции, технология), когда, кем
CREATE TABLE IF NOT EXISTS tech_card_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tech_card_id UUID NOT NULL REFERENCES tech_cards(id) ON DELETE CASCADE,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  changed_by_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
  changed_by_name TEXT,
  changes JSONB NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_tech_card_history_tech_card_id
  ON tech_card_history(tech_card_id);

CREATE INDEX IF NOT EXISTS idx_tech_card_history_changed_at
  ON tech_card_history(changed_at DESC);

COMMENT ON TABLE tech_card_history IS 'История изменений ТТК: что изменилось (ингредиенты, вес порции, технология и т.д.), когда, кем';

ALTER TABLE tech_card_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth_select_tech_card_history" ON tech_card_history
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid() OR id = auth.uid())
      UNION
      SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid() OR id = auth.uid()
    )
  );

CREATE POLICY "auth_insert_tech_card_history" ON tech_card_history
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (
      SELECT id FROM establishments WHERE owner_id IN (SELECT id FROM employees WHERE auth_user_id = auth.uid() OR id = auth.uid())
      UNION
      SELECT establishment_id FROM employees WHERE auth_user_id = auth.uid() OR id = auth.uid()
    )
  );

-- Legacy login (authenticate-employee) использует anon; история для них будет пустой до внедрения RPC/проверки сессии
