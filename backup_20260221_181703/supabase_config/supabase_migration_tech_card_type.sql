-- Тип ТТК: полуфабрикат (ПФ) или готовое блюдо. В инвентаризацию ПФ попадают только полуфабрикаты.
ALTER TABLE tech_cards ADD COLUMN IF NOT EXISTS is_semi_finished BOOLEAN DEFAULT true;
