-- ВОССТАНОВЛЕНИЕ РАБОЧИХ RLS ПОЛИТИК

-- Включаем RLS обратно
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE establishment_products ENABLE ROW LEVEL SECURITY;

-- Удаляем все сломанные политики
DROP POLICY IF EXISTS "employees_access_policy" ON employees;
DROP POLICY IF EXISTS "establishments_access_policy" ON establishments;
DROP POLICY IF EXISTS "products_access" ON products;
DROP POLICY IF EXISTS "establishment_products_access" ON establishment_products;

-- СОЗДАЕМ РАБОЧИЕ ПОЛИТИКИ (из оригинальной версии)
-- Эти политики должны быть в рабочей версии

-- Products: все авторизованные пользователи могут читать продукты
CREATE POLICY "products_access" ON products
FOR ALL USING (auth.uid() IS NOT NULL);

-- Establishment products: пользователи могут работать со своими продуктами
CREATE POLICY "establishment_products_access" ON establishment_products
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
));

-- Employees: пользователи могут читать сотрудников своего заведения + себя
CREATE POLICY "employees_establishment_access" ON employees
FOR ALL USING (establishment_id IN (
  SELECT establishment_id FROM employees WHERE id = auth.uid()
) OR id = auth.uid());

-- Establishments: владельцы могут работать со своими заведениями
CREATE POLICY "establishments_owner_access" ON establishments
FOR ALL USING (id IN (
  SELECT establishment_id FROM employees
  WHERE id = auth.uid() AND 'owner' = ANY(roles)
));

-- Проверяем созданные политики
SELECT
    tablename,
    policyname,
    qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;