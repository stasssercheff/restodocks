-- Пользовательские категории ТТК (свой вариант) для кухни и бара.
-- Сохраняются для повторного использования. Удалить можно только если ни одна ТТК не использует категорию.
CREATE TABLE IF NOT EXISTS tech_card_custom_categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  establishment_id UUID NOT NULL REFERENCES establishments(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  department TEXT NOT NULL CHECK (department IN ('kitchen', 'bar')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tech_card_custom_categories_est_dept_name
  ON tech_card_custom_categories(establishment_id, department, LOWER(TRIM(name)));
CREATE INDEX IF NOT EXISTS idx_tech_card_custom_categories_establishment
  ON tech_card_custom_categories(establishment_id, department);

COMMENT ON TABLE tech_card_custom_categories IS 'Пользовательские категории ТТК. В tech_cards.category хранится custom:{id}. Удаление разрешено только при отсутствии ТТК с этой категорией.';

ALTER TABLE tech_card_custom_categories ENABLE ROW LEVEL SECURITY;

-- RLS: доступ только для своего заведения
CREATE POLICY "auth_select_tech_card_custom_categories" ON tech_card_custom_categories
  FOR SELECT TO authenticated
  USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid() OR auth_user_id = auth.uid())
  );

CREATE POLICY "auth_insert_tech_card_custom_categories" ON tech_card_custom_categories
  FOR INSERT TO authenticated
  WITH CHECK (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid() OR auth_user_id = auth.uid())
  );

CREATE POLICY "auth_delete_tech_card_custom_categories" ON tech_card_custom_categories
  FOR DELETE TO authenticated
  USING (
    establishment_id IN (SELECT establishment_id FROM employees WHERE id = auth.uid() OR auth_user_id = auth.uid())
  );
