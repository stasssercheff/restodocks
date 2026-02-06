-- Тип оплаты и ставки сотрудника (почасовая / за смену).
-- Выполните в Supabase SQL Editor, если при сохранении сотрудника возникает ошибка PGRST204 (column hourly_rate not found).

ALTER TABLE employees ADD COLUMN IF NOT EXISTS payment_type TEXT DEFAULT 'hourly';
ALTER TABLE employees ADD COLUMN IF NOT EXISTS rate_per_shift REAL;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS hourly_rate REAL;

COMMENT ON COLUMN employees.payment_type IS 'hourly | per_shift';
COMMENT ON COLUMN employees.rate_per_shift IS 'Ставка за смену (если payment_type = per_shift)';
COMMENT ON COLUMN employees.hourly_rate IS 'Ставка в час (если payment_type = hourly)';
