-- Добавляем колонки для IP и геолокации при регистрации заведения
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS registration_ip TEXT;
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS registration_country TEXT;
ALTER TABLE establishments ADD COLUMN IF NOT EXISTS registration_city TEXT;

COMMENT ON COLUMN establishments.registration_ip IS 'IP адрес клиента при регистрации';
COMMENT ON COLUMN establishments.registration_country IS 'Страна по IP при регистрации';
COMMENT ON COLUMN establishments.registration_city IS 'Город по IP при регистрации';
