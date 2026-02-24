-- Добавление поля preferred_currency в таблицу employees

ALTER TABLE employees
ADD COLUMN IF NOT EXISTS preferred_currency TEXT DEFAULT 'RUB';

-- Комментарий для поля
COMMENT ON COLUMN employees.preferred_currency IS 'Предпочитаемая валюта пользователя (RUB, USD, VND, EUR, etc.)';