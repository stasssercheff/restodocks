-- Местоположение при последнем входе (для отображения пользователю и в админке)
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_ip TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_country TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_city TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

COMMENT ON COLUMN employees.last_login_ip IS 'IP при последнем входе';
COMMENT ON COLUMN employees.last_login_country IS 'Страна по IP при последнем входе';
COMMENT ON COLUMN employees.last_login_city IS 'Город по IP при последнем входе';
COMMENT ON COLUMN employees.last_login_at IS 'Время последнего входа';
