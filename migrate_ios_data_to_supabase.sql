-- Миграция данных из iOS Core Data в Supabase
-- Выполнить после экспорта данных из Core Data

-- Сначала проверим текущие данные
SELECT 'Current employees:' as info, COUNT(*) as count FROM employees;
SELECT 'Current establishments:' as info, COUNT(*) as count FROM establishments;

-- 1. Проверим, есть ли уже заведение Yummy
SELECT id, name, pin_code FROM establishments WHERE name = 'Yummy';

-- 2. Проверим, есть ли уже пользователь stassser@gmail.com
SELECT id, full_name, email FROM employees WHERE email = 'stassser@gmail.com';

-- Если данных нет, раскомментируйте вставки ниже:

-- INSERT INTO establishments (id, name, pin_code, default_currency, created_at, updated_at)
-- VALUES (
--     '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'::uuid,
--     'Yummy',
--     'GF0ABBBG',
--     'RUB',
--     NOW(),
--     NOW()
-- );

-- INSERT INTO employees (
--     id, full_name, email, password_hash, department,
--     establishment_id, personal_pin, roles, is_active,
--     created_at, updated_at
-- )
-- VALUES (
--     '3b57ec99-c59b-48ba-b3b8-affa3d664903'::uuid,
--     'Stas1',
--     'stassser@gmail.com',
--     '$2b$10$dummyhash', -- Замените на реальный BCrypt хеш пароля '1111!'
--     'management',
--     '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'::uuid,
--     NULL,
--     ARRAY['owner'],
--     true,
--     NOW(),
--     NOW()
-- );

-- UPDATE establishments
-- SET owner_id = '3b57ec99-c59b-48ba-b3b8-affa3d664903'::uuid
-- WHERE name = 'Yummy' AND owner_id IS NULL;

-- Финальная проверка
SELECT 'Migration check completed' as status;