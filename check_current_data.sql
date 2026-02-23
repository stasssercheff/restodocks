SELECT 'Current employees:' as info, COUNT(*) as count FROM employees;
SELECT 'Current establishments:' as info, COUNT(*) as count FROM establishments;
SELECT id, name, pin_code FROM establishments WHERE name = 'Yummy';
SELECT id, full_name, email FROM employees WHERE email = 'stassser@gmail.com';
