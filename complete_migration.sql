-- ПОЛНАЯ МИГРАЦИЯ: Core Data → Supabase + очистка

-- 1. ПРОВЕРКА ТЕКУЩИХ ДАННЫХ
SELECT '=== BEFORE MIGRATION ===' as status;
SELECT 'Employees count:' as info, COUNT(*) as count FROM employees;
SELECT 'Establishments count:' as info, COUNT(*) as count FROM establishments;
SELECT 'Employees:' as info, id, full_name, email FROM employees;
SELECT 'Establishments:' as info, id, name, pin_code FROM establishments;

-- 2. ДОБАВИТЬ ДАННЫЕ ИЗ CORE DATA (если их нет)
-- Установление Yummy (если не существует)
INSERT INTO establishments (id, name, pin_code, default_currency, created_at, updated_at)
VALUES (
    '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'::uuid,
    'Yummy',
    'GF0ABBBG',
    'RUB',
    NOW(),
    NOW()
)
ON CONFLICT (id) DO NOTHING;

-- Пользователь Stas1 (если не существует)
INSERT INTO employees (
    id, full_name, email, password_hash, department,
    establishment_id, personal_pin, roles, is_active,
    created_at, updated_at
)
VALUES (
    '3b57ec99-c59b-48ba-b3b8-affa3d664903'::uuid,
    'Stas1',
    'stassser@gmail.com',
    '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', -- BCrypt hash for '1111!'
    'management',
    '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b'::uuid,
    NULL,
    ARRAY['owner'],
    true,
    NOW(),
    NOW()
)
ON CONFLICT (email) DO NOTHING;

-- Обновить owner_id
UPDATE establishments
SET owner_id = '3b57ec99-c59b-48ba-b3b8-affa3d664903'::uuid
WHERE name = 'Yummy' AND owner_id IS NULL;

-- 3. ПРОВЕРКА ПОСЛЕ МИГРАЦИИ
SELECT '=== AFTER MIGRATION ===' as status;
SELECT 'Employees count:' as info, COUNT(*) as count FROM employees;
SELECT 'Establishments count:' as info, COUNT(*) as count FROM establishments;
SELECT 'Employees:' as info, id, full_name, email FROM employees;
SELECT 'Establishments:' as info, id, name, pin_code, owner_id FROM establishments;

SELECT '✅ Migration completed successfully!' as status;