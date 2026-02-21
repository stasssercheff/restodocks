-- ПРОВЕРКА СОСТОЯНИЯ БАЗЫ ДАННЫХ

-- 1. КОЛИЧЕСТВО ЗАПИСЕЙ В КАЖДОЙ ТАБЛИЦЕ
SELECT
  'employees' as table_name,
  COUNT(*) as total_count
FROM employees
UNION ALL
SELECT
  'establishments' as table_name,
  COUNT(*) as total_count
FROM establishments
UNION ALL
SELECT
  'products' as table_name,
  COUNT(*) as total_count
FROM products
UNION ALL
SELECT
  'establishment_products' as table_name,
  COUNT(*) as total_count
FROM establishment_products
UNION ALL
SELECT
  'tech_cards' as table_name,
  COUNT(*) as total_count
FROM tech_cards
UNION ALL
SELECT
  'checklists' as table_name,
  COUNT(*) as total_count
FROM checklists
ORDER BY table_name;

-- 2. ПРОВЕРКА ПОЛЬЗОВАТЕЛЕЙ И ЗАВЕДЕНИЙ
SELECT
  e.id,
  e.name,
  e.owner_id,
  emp.full_name as owner_name,
  emp.email as owner_email,
  emp.roles
FROM establishments e
LEFT JOIN employees emp ON e.owner_id = emp.id;

-- 3. ПРОВЕРКА ПРОДУКТОВ ЗАВЕДЕНИЯ (если есть данные)
SELECT
  ep.establishment_id,
  e.name as establishment_name,
  COUNT(ep.*) as products_count,
  COUNT(CASE WHEN ep.price > 0 THEN 1 END) as with_price_count
FROM establishment_products ep
JOIN establishments e ON ep.establishment_id = e.id
GROUP BY ep.establishment_id, e.name;

-- 4. ПРОВЕРКА ТТК
SELECT
  tc.id,
  tc.name,
  tc.establishment_id,
  e.name as establishment_name,
  COUNT(ti.*) as ingredients_count
FROM tech_cards tc
LEFT JOIN establishments e ON tc.establishment_id = e.id
LEFT JOIN tt_ingredients ti ON tc.id = ti.tech_card_id
GROUP BY tc.id, tc.name, tc.establishment_id, e.name;

-- 5. ПРОВЕРКА ЧЕКЛИСТОВ
SELECT
  c.id,
  c.name,
  c.establishment_id,
  e.name as establishment_name,
  COUNT(ci.*) as items_count
FROM checklists c
LEFT JOIN establishments e ON c.establishment_id = e.id
LEFT JOIN checklist_items ci ON c.id = ci.checklist_id
GROUP BY c.id, c.name, c.establishment_id, e.name;