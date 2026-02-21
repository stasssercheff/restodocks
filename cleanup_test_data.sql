-- ОЧИСТКА ТЕСТОВЫХ ДАННЫХ
-- ВЫПОЛНИТЬ В SUPABASE SQL EDITOR

-- 1. ПОСМОТРЕТЬ ТЕКУЩИЕ ЗАВЕДЕНИЯ И ВЛАДЕЛЬЦЕВ
SELECT
  e.id,
  e.name,
  e.owner_id,
  emp.full_name as owner_name,
  emp.email as owner_email,
  emp.created_at
FROM establishments e
LEFT JOIN employees emp ON e.owner_id = emp.id
ORDER BY emp.created_at DESC;

-- 2. ПОСМОТРЕТЬ ВСЕХ СОТРУДНИКОВ
SELECT
  emp.id,
  emp.full_name,
  emp.email,
  emp.roles,
  emp.is_active,
  emp.created_at,
  e.name as establishment_name
FROM employees emp
LEFT JOIN establishments e ON emp.establishment_id = e.id
ORDER BY emp.created_at DESC;

-- 3. ДЕАКТИВИРОВАТЬ ТЕСТОВЫХ СОТРУДНИКОВ (НЕ УДАЛЯТЬ ПОЛНОСТЬЮ)
-- Раскомментируйте и замените ID на реальные ID тестовых сотрудников
/*
UPDATE employees
SET is_active = false
WHERE id IN (
  'test-employee-id-1',
  'test-employee-id-2'
);
*/

-- 4. ПОЛНОСТЬЮ УДАЛИТЬ ЗАВЕДЕНИЕ И ВСЕ СВЯЗАННЫЕ ДАННЫЕ
-- ⚠️ ОПАСНО! УДАЛЯЕТ ВСЕ ДАННЫЕ ЗАВЕДЕНИЯ
-- Раскомментируйте и замените establishment_id на реальный ID
/*
-- Удаляем продукты заведения
DELETE FROM establishment_products WHERE establishment_id = 'your-establishment-id';

-- Удаляем ТТК
DELETE FROM tech_cards WHERE establishment_id = 'your-establishment-id';

-- Удаляем чеклисты
DELETE FROM checklists WHERE establishment_id = 'your-establishment-id';

-- Удаляем элементы чеклистов
DELETE FROM checklist_items WHERE checklist_id NOT IN (SELECT id FROM checklists);

-- Удаляем ингредиенты ТТК
DELETE FROM tt_ingredients WHERE tech_card_id NOT IN (SELECT id FROM tech_cards);

-- Удаляем сотрудников (деактивируем, не удаляем)
UPDATE employees SET is_active = false WHERE establishment_id = 'your-establishment-id';

-- Наконец, удаляем заведение
DELETE FROM establishments WHERE id = 'your-establishment-id';
*/