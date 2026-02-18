-- Добавление поля subscription_plan в таблицу employees
-- Это поле будет определять тип подписки пользователя (free/pro/premium)

ALTER TABLE employees
ADD COLUMN IF NOT EXISTS subscription_plan TEXT DEFAULT 'free'
CHECK (subscription_plan IN ('free', 'pro', 'premium'));

-- Обновляем существующих пользователей на free подписку
UPDATE employees
SET subscription_plan = 'free'
WHERE subscription_plan IS NULL;

-- Добавляем комментарий к полю
COMMENT ON COLUMN employees.subscription_plan IS 'Тип подписки пользователя: free, pro, premium';

-- Создаем индекс для быстрого поиска по подписке
CREATE INDEX IF NOT EXISTS idx_employees_subscription_plan
ON employees(subscription_plan);