-- Продажная стоимость блюда/напитка. Устанавливается шеф-поваром (кухня) и барменеджером (бар).
ALTER TABLE tech_cards
  ADD COLUMN IF NOT EXISTS selling_price NUMERIC(12, 2);

COMMENT ON COLUMN tech_cards.selling_price IS 'Продажная стоимость блюда/напитка. Шеф — кухня, барменеджер — бар.';
