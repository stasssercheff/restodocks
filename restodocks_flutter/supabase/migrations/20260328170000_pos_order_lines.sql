-- Позиции заказа зала (блюда из ТТК: порции, комментарий, курс, гость).
CREATE TABLE IF NOT EXISTS pos_order_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES pos_orders(id) ON DELETE CASCADE,
  tech_card_id UUID NOT NULL REFERENCES tech_cards(id) ON DELETE RESTRICT,
  quantity NUMERIC NOT NULL DEFAULT 1 CHECK (quantity > 0),
  comment TEXT,
  course_number INT NOT NULL DEFAULT 1 CHECK (course_number >= 1),
  guest_number INT CHECK (guest_number IS NULL OR guest_number >= 1),
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pos_order_lines_order ON pos_order_lines(order_id);
CREATE INDEX IF NOT EXISTS idx_pos_order_lines_tech_card ON pos_order_lines(tech_card_id);

COMMENT ON TABLE pos_order_lines IS 'Позиции счёта зала: ТТК, количество порций, комментарий, курс подачи, номер гостя.';

ALTER TABLE pos_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_pos_order_lines_all" ON pos_order_lines;
CREATE POLICY "anon_pos_order_lines_all" ON pos_order_lines
  FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_pos_order_lines_all" ON pos_order_lines;
CREATE POLICY "auth_pos_order_lines_all" ON pos_order_lines
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
