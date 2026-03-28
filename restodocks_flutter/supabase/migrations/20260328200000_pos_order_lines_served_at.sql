-- Когда позиция отдана гостю (кухня/бар отмечает в POS).
ALTER TABLE pos_order_lines
  ADD COLUMN IF NOT EXISTS served_at TIMESTAMPTZ;

COMMENT ON COLUMN pos_order_lines.served_at IS 'Время отдачи гостю; NULL — ещё в работе/ожидает.';
