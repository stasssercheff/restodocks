-- ПОЛНЫЙ РЕМОНТ БАЗЫ ДАННЫХ ПОСЛЕ ЭКСПЕРИМЕНТОВ С RLS
-- Выполнить в Supabase SQL Editor

-- 1. ВКЛЮЧАЕМ RLS НА ВСЕХ ТАБЛИЦАХ
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;

-- 2. УДАЛЯЕМ ВСЕ СТАРЫЕ ПОЛИТИКИ
DROP POLICY IF EXISTS "products_access" ON products;
DROP POLICY IF EXISTS "establishment_products_access" ON establishment_products;
DROP POLICY IF EXISTS "employees_establishment_access" ON employees;
DROP POLICY IF EXISTS "establishments_owner_access" ON establishments;

-- 3. СОЗДАЕМ ПРАВИЛЬНЫЕ ПОЛИТИКИ
-- Products: все авторизованные пользователи могут видеть все продукты
CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

-- Establishment products: пользователи видят продукты своего заведения
CREATE POLICY "establishment_products_access" ON establishment_products
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Employees: сотрудники видят коллег из своего заведения
CREATE POLICY "employees_establishment_access" ON employees
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Establishments: владелец видит свое заведение
CREATE POLICY "establishments_owner_access" ON establishments
FOR ALL USING (id IN (
  SELECT establishment_id FROM employees
  WHERE id = auth.uid() AND 'owner' = ANY(roles)
));

-- 4. ПРОВЕРКА РЕЗУЛЬТАТА
SELECT
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('products', 'establishment_products', 'employees', 'establishments')
ORDER BY tablename;

-- 5. ПРОВЕРКА ДАННЫХ
SELECT COUNT(*) as products_count FROM products;
SELECT
    establishment_id,
    COUNT(*) as establishment_products_count
FROM establishment_products
GROUP BY establishment_id;

-- 6. ТЕСТ ЗАПРОСОВ
SELECT id, name, category FROM products LIMIT 3;
SELECT product_id, price, currency FROM establishment_products WHERE establishment_id = '35e5ec5b-a57a-49f5-b4b0-02cfa8b6b17b' LIMIT 3;