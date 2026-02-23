-- ЧАСТЬ 4: Индексы и триггеры
-- Выполните в последнюю очередь

-- Индексы для производительности
CREATE INDEX idx_employees_establishment_id ON employees(establishment_id);
CREATE INDEX idx_employees_email ON employees(email);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_tech_cards_establishment_id ON tech_cards(establishment_id);
CREATE INDEX idx_tt_ingredients_tech_card_id ON tt_ingredients(tech_card_id);

-- Функция для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Триггеры для автоматического обновления updated_at
CREATE TRIGGER update_establishments_updated_at BEFORE UPDATE ON establishments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_employees_updated_at BEFORE UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tech_cards_updated_at BEFORE UPDATE ON tech_cards FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();