-- tech_cards: anon SELECT для выбора ТТК ПФ в чеклистах и др.
-- Приложение использует anon-ключ; без этой политики getTechCardsForEstablishment возвращает [].
ALTER TABLE tech_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_tech_cards_select" ON tech_cards;
CREATE POLICY "anon_tech_cards_select" ON tech_cards
  FOR SELECT TO anon USING (true);
