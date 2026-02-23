-- Тест входа для stassser@gmail.com

-- Проверить данные пользователя
SELECT 'Stassser account data:' as info;
SELECT id, full_name, email, password_hash, auth_user_id, establishment_id, roles
FROM employees
WHERE email = 'stassser@gmail.com';

-- Проверить заведение
SELECT 'Establishment data:' as info;
SELECT id, name, pin_code, owner_id
FROM establishments
WHERE name = 'Yummy';

-- Проверить связь
SELECT 'Relationship check:' as info,
  e.full_name, e.email, est.name as establishment_name, est.pin_code
FROM employees e
JOIN establishments est ON e.establishment_id = est.id
WHERE e.email = 'stassser@gmail.com';